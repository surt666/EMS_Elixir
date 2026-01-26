defmodule EmsBackend.Repositories.HierarchyValkeyImpl do
  @moduledoc """
  Valkey/Redis implementation of HierarchyRepository.

  Implements hexastore-style indexing with 6 indices per edge for efficient bidirectional traversal:
  - SPO: edge:{parent}:has_child:{child} - direct parent-to-child lookup
  - SOP: edge:{parent}:{child}:has_child - find relationship by parent and child
  - PSO: edge:has_child:{parent}:{child} - find all children of a parent
  - POS: edge:has_child:{child}:{parent} - find all parents of a child
  - OSP: edge:{child}:{parent}:has_child - find relationship by child and parent
  - OPS: edge:{child}:has_child:{parent} - direct child-to-parent lookup

  The 6 permutations allow O(1) bidirectional queries without redundant indices.
  """

  @behaviour EmsBackend.Repositories.HierarchyRepository

  alias EmsBackend.Domain.HierarchyNode

  @doc """
  Stores a hierarchy node in Valkey.
  Key format: node:Type#123
  """
  @impl true
  def create(node) do
    key = node_key(node.type, node.id)
    json = serialize_node(node)

    case Redix.command(:redix, ["SET", key, json]) do
      {:ok, "OK"} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Retrieves a hierarchy node by type and ID.
  """
  @impl true
  def get(type, id) do
    key = node_key(type, id)

    case Redix.command(:redix, ["GET", key]) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, json} -> {:ok, deserialize_node(json)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Creates a parent-child relationship with hexastore indexing and descendant sets.

  Stores 6 keys with all permutations of (subject, predicate, object):
  - SPO: edge:{parent}:has_child:{child}
  - SOP: edge:{parent}:{child}:has_child
  - PSO: edge:has_child:{parent}:{child}
  - POS: edge:has_child:{child}:{parent}
  - OSP: edge:{child}:{parent}:has_child
  - OPS: edge:{child}:has_child:{parent}

  Additionally maintains descendant sets for O(1) queries:
  - descendants:{parent}:{child_type} → Set of all descendants of that type
  - Updates all ancestor descendant sets transitively
  """
  @impl true
  def link_child(parent_node, child_node) do
    parent_ref = node_ref(parent_node.type, parent_node.id)
    child_ref = node_ref(child_node.type, child_node.id)

    edge_data = %{
      parent_id: parent_ref,
      child_id: child_ref,
      parent_type: parent_node.type,
      child_type: child_node.type,
      parent_name: parent_node.name,
      child_name: child_node.name,
      created: DateTime.utc_now() |> DateTime.to_iso8601()
    } |> Msgpax.pack!(iodata: false)

    # Generate 6 hexastore keys
    keys = hexastore_keys(parent_ref, "has_child", child_ref)

    # Store all 6 indices
    results = Enum.map(Map.values(keys), fn key ->
      case Redix.command(:redix, ["SET", key, edge_data]) do
        {:ok, "OK"} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end)

    # Verify all sets succeeded
    with true <- Enum.all?(results, &(&1 == :ok)),
         :ok <- add_to_descendant_sets(parent_node, child_node) do
      :ok
    else
      false -> {:error, :failed_to_create_indices}
      error -> error
    end
  end

  @doc """
  Gets all children of a node.
  Uses the PSO index: edge:has_child:{parent}:*
  Filters results to ensure parent_id matches the queried node.
  """
  @impl true
  def get_children(type, id) do
    parent_ref = node_ref(type, id)
    pattern = "edge:has_child:#{parent_ref}:*"

    case Redix.command(:redix, ["KEYS", pattern]) do
      {:ok, keys} ->
        children = Enum.flat_map(keys, fn key ->
          case Redix.command(:redix, ["GET", key]) do
            {:ok, edge_msgpack} ->
              {:ok, edge_data} = Msgpax.unpack(edge_msgpack)

              if edge_data["parent_id"] == parent_ref do
                [%{
                  id: extract_id(edge_data["child_id"]),
                  type: extract_type(edge_data["child_id"]),
                  name: edge_data["child_name"],
                  ref: edge_data["child_id"]
                }]
              else
                []
              end
            _ -> []
          end
        end)
        {:ok, children}

      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets the parent of a node.
  Uses the OPS index: edge:{child}:has_child:*
  Filters results to ensure child_id matches the queried node.
  """
  @impl true
  def get_parent(type, id) do
    child_ref = node_ref(type, id)
    pattern = "edge:#{child_ref}:has_child:*"

    case Redix.command(:redix, ["KEYS", pattern]) do
      {:ok, []} -> {:ok, nil}
      {:ok, keys} ->
        # Filter to find the edge where this node is actually the child
        parent_edge = Enum.find_value(keys, fn key ->
          case Redix.command(:redix, ["GET", key]) do
            {:ok, edge_msgpack} ->
              {:ok, edge_data} = Msgpax.unpack(edge_msgpack)

              if edge_data["child_id"] == child_ref do
                %{
                  id: extract_id(edge_data["parent_id"]),
                  type: extract_type(edge_data["parent_id"]),
                  name: edge_data["parent_name"],
                  ref: edge_data["parent_id"]
                }
              end
            _ -> nil
          end
        end)

        if parent_edge, do: {:ok, parent_edge}, else: {:ok, nil}

      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Removes a parent-child relationship.
  Deletes all 6 hexastore indices and updates descendant sets.
  """
  @impl true
  def unlink_child(parent_type, parent_id, child_type, child_id) do
    parent_ref = node_ref(parent_type, parent_id)
    child_ref = node_ref(child_type, child_id)

    # Delete all 6 hexastore keys
    keys = hexastore_keys(parent_ref, "has_child", child_ref)

    Enum.each(Map.values(keys), fn key ->
      Redix.command(:redix, ["DEL", key])
    end)

    # Remove from descendant sets
    remove_from_descendant_sets(parent_type, parent_id, child_type, child_id)

    :ok
  end

  @doc """
  Gets full path from node to root (ancestors).
  """
  @impl true
  def get_ancestors(type, id) do
    get_ancestors_recursive(type, id, [])
  end

  @doc """
  Gets all descendants of a node (recursive children).
  """
  @impl true
  def get_descendants(type, id) do
    get_descendants_recursive(type, id, [])
  end

  @doc """
  Gets all descendants of a specific type using materialized descendant sets.
  This is O(1) instead of recursive traversal.
  """
  @impl true
  def get_descendants_by_type(type, id, descendant_type) do
    ancestor_ref = node_ref(type, id)
    type_key = type_to_descendant_key(descendant_type)
    set_key = "descendants:#{ancestor_ref}:#{type_key}"

    case Redix.command(:redix, ["SMEMBERS", set_key]) do
      {:ok, refs} ->
        # Convert refs back to maps with id and type
        descendants = Enum.map(refs, fn ref ->
          id = extract_id(ref)
          %{id: id, type: descendant_type, ref: ref}
        end)
        {:ok, descendants}
      {:error, reason} -> {:error, reason}
    end
  end

  # Private helper functions

  # Convert atom type to capitalized string for storage keys
  # Convert node type to short code for compact storage
  defp type_to_string(:root), do: "R"
  defp type_to_string(:partner), do: "P"
  defp type_to_string(:company), do: "C"
  defp type_to_string(:property), do: "PR"
  defp type_to_string(:building), do: "B"
  defp type_to_string(:area), do: "A"
  defp type_to_string(:group), do: "G"
  defp type_to_string(type) when is_binary(type) do
    # Handle string input by converting to atom first
    type
    |> String.downcase()
    |> String.to_existing_atom()
    |> type_to_string()
  end

  # Convert short code back to atom type
  defp string_to_type("R"), do: :root
  defp string_to_type("P"), do: :partner
  defp string_to_type("C"), do: :company
  defp string_to_type("PR"), do: :property
  defp string_to_type("B"), do: :building
  defp string_to_type("A"), do: :area
  defp string_to_type("G"), do: :group

  # Convert type atom to full lowercase name for descendant set keys
  defp type_to_descendant_key(:root), do: "root"
  defp type_to_descendant_key(:partner), do: "partner"
  defp type_to_descendant_key(:company), do: "company"
  defp type_to_descendant_key(:property), do: "property"
  defp type_to_descendant_key(:building), do: "building"
  defp type_to_descendant_key(:area), do: "area"
  defp type_to_descendant_key(:group), do: "group"
  defp type_to_descendant_key(type) when is_binary(type) do
    # Handle string input by converting to atom first
    type
    |> String.downcase()
    |> String.to_existing_atom()
    |> type_to_descendant_key()
  end

  defp node_key(type, id) do
    type_str = type_to_string(type)
    "node:#{type_str}##{id}"
  end

  defp node_ref(type, id) do
    type_str = type_to_string(type)
    "#{type_str}##{id}"
  end

  defp extract_id(ref) do
    [_type, id] = String.split(ref, "#", parts: 2)
    String.to_integer(id)
  end

  defp extract_type(ref) do
    [type_str, _id] = String.split(ref, "#", parts: 2)
    string_to_type(type_str)
  end

  defp hexastore_keys(subject, predicate, object) do
    %{
      spo: "edge:#{subject}:#{predicate}:#{object}",
      sop: "edge:#{subject}:#{object}:#{predicate}",
      pso: "edge:#{predicate}:#{subject}:#{object}",
      pos: "edge:#{predicate}:#{object}:#{subject}",
      osp: "edge:#{object}:#{subject}:#{predicate}",
      ops: "edge:#{object}:#{predicate}:#{subject}"
    }
  end

  defp serialize_node(node) do
    %{
      id: node.id,
      created: DateTime.to_iso8601(node.created),
      type: node.type,
      name: node.name,
      metadata: node.metadata,
      blocked: node.blocked,
      parent: node.parent
    }
    |> Msgpax.pack!(iodata: false)
  end

  defp deserialize_node(msgpack_binary) do
    {:ok, data} = Msgpax.unpack(msgpack_binary)
    {:ok, created, _} = DateTime.from_iso8601(data["created"])

    %HierarchyNode{
      id: data["id"],
      created: created,
      type: String.to_existing_atom(data["type"]),
      name: data["name"],
      metadata: atomize_metadata_keys(data["metadata"]),
      blocked: data["blocked"],
      parent: data["parent"]
    }
  end

  # Recursively convert string keys to atoms in metadata maps
  defp atomize_metadata_keys(metadata) when is_map(metadata) do
    metadata
    |> Enum.map(fn {key, value} ->
      atom_key = if is_binary(key), do: String.to_existing_atom(key), else: key
      atom_value = if is_map(value), do: atomize_metadata_keys(value), else: value
      {atom_key, atom_value}
    end)
    |> Enum.into(%{})
  end
  defp atomize_metadata_keys(metadata), do: metadata

  defp get_ancestors_recursive(type, id, acc) do
    case get_parent(type, id) do
      {:ok, nil} -> {:ok, Enum.reverse(acc)}
      {:ok, parent} ->
        # Detect cycles - check if we've already seen this parent
        if Enum.any?(acc, fn ancestor -> ancestor.type == parent.type and ancestor.id == parent.id end) do
          {:error, :cycle_detected}
        else
          get_ancestors_recursive(parent.type, parent.id, [parent | acc])
        end
      error -> error
    end
  end

  defp get_descendants_recursive(type, id, visited) do
    # Detect cycles by checking if we've already visited this node
    node_key = {type, id}
    if Enum.member?(visited, node_key) do
      {:error, :cycle_detected}
    else
      case get_children(type, id) do
        {:ok, []} -> {:ok, []}
        {:ok, children} ->
          new_visited = [node_key | visited]
          descendants = Enum.flat_map(children, fn child ->
            case get_descendants_recursive(child.type, child.id, new_visited) do
              {:ok, child_descendants} -> [child | child_descendants]
              _ -> [child]
            end
          end)
          {:ok, descendants}
        error -> error
      end
    end
  end

  # Adds child and all its descendants to parent and all ancestor descendant sets
  defp add_to_descendant_sets(parent_node, child_node) do
    parent_ref = node_ref(parent_node.type, parent_node.id)
    child_ref = node_ref(child_node.type, child_node.id)

    # Get all descendants of the child (to maintain transitive closure)
    child_descendants = case get_descendants(child_node.type, child_node.id) do
      {:ok, descendants} -> descendants
      _ -> []
    end

    # Collect all nodes to add: child + all its descendants
    nodes_to_add = [%{ref: child_ref, type: child_node.type} |
                    Enum.map(child_descendants, fn d -> %{ref: node_ref(d.type, d.id), type: d.type} end)]

    # Add to parent's descendant sets
    with :ok <- add_nodes_to_descendant_sets(parent_ref, nodes_to_add) do
      # Get all ancestors of parent and add to their descendant sets too
      case get_ancestors(parent_node.type, parent_node.id) do
        {:ok, ancestors} ->
          Enum.reduce_while(ancestors, :ok, fn ancestor, _acc ->
            ancestor_ref = node_ref(ancestor.type, ancestor.id)
            case add_nodes_to_descendant_sets(ancestor_ref, nodes_to_add) do
              :ok -> {:cont, :ok}
              error -> {:halt, error}
            end
          end)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # Helper to add multiple nodes to an ancestor's descendant sets (grouped by type)
  defp add_nodes_to_descendant_sets(ancestor_ref, nodes) do
    # Group nodes by type
    nodes_by_type = Enum.group_by(nodes, & &1.type, & &1.ref)

    # For each type, add all refs to the set
    results = Enum.map(nodes_by_type, fn {type, refs} ->
      type_key = type_to_descendant_key(type)
      set_key = "descendants:#{ancestor_ref}:#{type_key}"

      # Use SADD with multiple members
      case Redix.command(:redix, ["SADD", set_key | refs]) do
        {:ok, _count} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end)

    if Enum.all?(results, &(&1 == :ok)) do
      :ok
    else
      {:error, :failed_to_update_descendant_sets}
    end
  end

  # Removes child and all its descendants from parent and all ancestor descendant sets
  defp remove_from_descendant_sets(parent_type, parent_id, child_type, child_id) do
    parent_ref = node_ref(parent_type, parent_id)
    child_ref = node_ref(child_type, child_id)

    # Get all descendants of the child (to maintain transitive closure)
    child_descendants = case get_descendants(child_type, child_id) do
      {:ok, descendants} -> descendants
      _ -> []
    end

    # Collect all nodes to remove: child + all its descendants
    nodes_to_remove = [%{ref: child_ref, type: child_type} |
                       Enum.map(child_descendants, fn d -> %{ref: node_ref(d.type, d.id), type: d.type} end)]

    # Remove from parent's descendant sets
    remove_nodes_from_descendant_sets(parent_ref, nodes_to_remove)

    # Get all ancestors of parent and remove from their descendant sets too
    case get_ancestors(parent_type, parent_id) do
      {:ok, ancestors} ->
        Enum.each(ancestors, fn ancestor ->
          ancestor_ref = node_ref(ancestor.type, ancestor.id)
          remove_nodes_from_descendant_sets(ancestor_ref, nodes_to_remove)
        end)
      _ -> :ok
    end

    :ok
  end

  # Helper to remove multiple nodes from an ancestor's descendant sets (grouped by type)
  defp remove_nodes_from_descendant_sets(ancestor_ref, nodes) do
    # Group nodes by type
    nodes_by_type = Enum.group_by(nodes, & &1.type, & &1.ref)

    # For each type, remove all refs from the set
    Enum.each(nodes_by_type, fn {type, refs} ->
      type_key = type_to_descendant_key(type)
      set_key = "descendants:#{ancestor_ref}:#{type_key}"

      # Use SREM with multiple members
      Redix.command(:redix, ["SREM", set_key | refs])
    end)

    :ok
  end
end
