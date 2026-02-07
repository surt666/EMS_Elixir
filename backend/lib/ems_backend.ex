defmodule EmsBackend do
  @moduledoc """
  EmsBackend context for managing hierarchy nodes.

  This module provides the public API for creating and managing
  organizational hierarchy nodes (Partner, Company, Property, Building, Area, Group).

  Uses HierarchyValkeyImpl as the default repository implementation.
  """

  alias EmsBackend.Domain.HierarchyNode
  alias EmsBackend.Repositories.HierarchyValkeyImpl

  @allowed_parents %{
    partner: [:root],
    company: [:partner],
    property: [:company],
    group: [:company, :property],
    building: [:company, :property, :group],
    area: [:building]
  }

  @doc """
  Creates a new hierarchy node and stores it.

  Automatically links the node to its parent. All nodes except Root must have a parent.
  Partner nodes default to Root#1 if no parent is specified.

  ## Parameters
  - `attrs` - Map with node attributes:
    - `:id` - Integer ID (optional, will be generated if not provided)
    - `:type` - Atom type: `:root`, `:partner`, `:company`, `:property`, `:building`, `:area`, `:group`
    - `:name` - String name
    - `:metadata` - Required map of type-specific metadata
    - `:blocked` - Boolean, defaults to false
  - `parent_ref` - Parent node reference (e.g., "Company#101"). Required for all types except:
    - Root nodes (must pass nil or omit)
    - Partner nodes (defaults to "Root#1" if not provided)

  ## Examples

      iex> create_hierarchy_node(%{name: "Acme Corp", type: :company, metadata: company_metadata()}, "Partner#1")
      {:ok, %HierarchyNode{type: :company, ...}}

      iex> create_hierarchy_node(%{name: "My Partner", type: :partner, metadata: partner_metadata()})
      {:ok, %HierarchyNode{type: :partner, parent: "Root#1"}}

      iex> create_hierarchy_node(%{name: "Property", type: :property, metadata: property_metadata()})
      {:error, "Parent is required for property nodes"}
  """
  def create_hierarchy_node(attrs, parent_ref \\ nil) do
    # Ensure Root#1 exists
    ensure_root_exists()

    # Validate and determine actual parent
    with {:ok, actual_parent_ref} <- validate_and_determine_parent(attrs[:type], parent_ref),
         {:ok, node} <- HierarchyNode.new(attrs),
         :ok <- HierarchyValkeyImpl.create(node),
         :ok <- maybe_link_to_parent(node, actual_parent_ref) do
      {:ok, node}
    end
  end

  # Private helpers

  defp ensure_root_exists do
    case HierarchyValkeyImpl.get("Root", 1) do
      {:ok, _root} ->
        :ok

      {:error, :not_found} ->
        {:ok, root} = HierarchyNode.new(%{id: 1, type: :root, name: "Root", metadata: %{}})
        HierarchyValkeyImpl.create(root)

      _ ->
        :ok
    end
  end

  defp validate_and_determine_parent(:root, _), do: {:ok, nil}
  defp validate_and_determine_parent(:partner, nil), do: {:ok, "Root#1"}

  defp validate_and_determine_parent(child_type, nil),
    do: {:error, "Parent is required for #{child_type} nodes"}

  defp validate_and_determine_parent(child_type, parent_ref) do
    [parent_type_str | _] = String.split(parent_ref, "#")
    parent_type = parent_type_str |> String.downcase() |> String.to_existing_atom()

    if parent_type in Map.get(@allowed_parents, child_type, []),
      do: {:ok, parent_ref},
      else: {:error, "#{child_type} cannot be a child of #{parent_type}"}
  end

  defp maybe_link_to_parent(_node, nil), do: :ok

  defp maybe_link_to_parent(node, parent_ref) do
    # Parse parent_ref to get type and id
    [parent_type_str, parent_id_str] = String.split(parent_ref, "#")
    parent_id = String.to_integer(parent_id_str)

    case HierarchyValkeyImpl.get(parent_type_str, parent_id) do
      {:ok, parent_node} ->
        HierarchyValkeyImpl.link_child(parent_node, node)

      error ->
        error
    end
  end

  @doc """
  Gets a hierarchy node by type and ID.

  ## Examples

      iex> get_hierarchy_node("Company", 1001)
      {:ok, %HierarchyNode{}}

      iex> get_hierarchy_node("Company", 999)
      {:error, :not_found}
  """
  def get_hierarchy_node(type, id) do
    HierarchyValkeyImpl.get(type, id)
  end

  @doc """
  Links a child node to a parent node in the hierarchy.

  Creates bidirectional hexastore indices for efficient traversal.

  ## Examples

      iex> link_hierarchy_nodes(parent_node, child_node)
      :ok
  """
  def link_hierarchy_nodes(parent_node, child_node) do
    HierarchyValkeyImpl.link_child(parent_node, child_node)
  end

  @doc """
  Gets all children of a hierarchy node.

  ## Options
  - `:exclude_blocked` - When true, filters out blocked nodes (default: false)

  ## Examples

      iex> get_hierarchy_children("Company", 1001)
      {:ok, [%{id: 2001, type: "Property", name: "Building A", ref: "Property#2001"}]}

      iex> get_hierarchy_children("Company", 1001, exclude_blocked: true)
      {:ok, [%{id: 2001, type: "Property", name: "Building A", ref: "Property#2001"}]}
  """
  def get_hierarchy_children(type, id, opts \\ []) do
    with {:ok, children} <- HierarchyValkeyImpl.get_children(type, id) do
      {:ok, maybe_filter_blocked(children, opts[:exclude_blocked])}
    end
  end

  defp maybe_filter_blocked(children, false), do: children
  defp maybe_filter_blocked(children, nil), do: children

  defp maybe_filter_blocked(children, true) do
    Enum.reject(children, fn child ->
      match?({:ok, %{blocked: true}}, HierarchyValkeyImpl.get(child.type, child.id))
    end)
  end

  @doc """
  Gets the parent of a hierarchy node.

  ## Examples

      iex> get_hierarchy_parent("Property", 2001)
      {:ok, %{id: 1001, type: "Company", name: "Acme Corp", ref: "Company#1001"}}

      iex> get_hierarchy_parent("Partner", 1)
      {:ok, nil}
  """
  def get_hierarchy_parent(type, id) do
    HierarchyValkeyImpl.get_parent(type, id)
  end

  @doc """
  Gets all ancestors of a hierarchy node (recursive).

  Returns list from immediate parent to root.

  ## Examples

      iex> get_hierarchy_ancestors("Building", 3001)
      {:ok, [
        %{id: 2001, type: "Property", name: "Property A"},
        %{id: 1001, type: "Company", name: "Acme Corp"}
      ]}
  """
  def get_hierarchy_ancestors(type, id) do
    HierarchyValkeyImpl.get_ancestors(type, id)
  end

  @doc """
  Gets all descendants of a hierarchy node (recursive).

  Returns flat list of all children, grandchildren, etc.

  ## Examples

      iex> get_hierarchy_descendants("Company", 1001)
      {:ok, [
        %{id: 2001, type: "Property", name: "Property A"},
        %{id: 3001, type: "Building", name: "Building 1"}
      ]}
  """
  def get_hierarchy_descendants(type, id) do
    HierarchyValkeyImpl.get_descendants(type, id)
  end

  @doc """
  Gets all descendants of a specific type using materialized descendant sets.
  This is O(1) instead of recursive traversal, making it much faster for large hierarchies.

  For example, to get all buildings under a company without traversing through properties:
  get_hierarchy_descendants_by_type("Company", 101, :building)

  ## Examples

      iex> get_hierarchy_descendants_by_type("Company", 1001, :building)
      {:ok, [
        %{id: 3001, type: :building, ref: "Building#3001"},
        %{id: 3002, type: :building, ref: "Building#3002"}
      ]}
  """
  def get_hierarchy_descendants_by_type(type, id, descendant_type) do
    HierarchyValkeyImpl.get_descendants_by_type(type, id, descendant_type)
  end

  @doc """
  Removes the parent-child relationship between two nodes.

  ## Examples

      iex> unlink_hierarchy_nodes("Company", 1001, "Property", 2001)
      :ok
  """
  def unlink_hierarchy_nodes(parent_type, parent_id, child_type, child_id) do
    HierarchyValkeyImpl.unlink_child(parent_type, parent_id, child_type, child_id)
  end

  # Permission management functions

  @doc """
  Grants a permission to a user on a specific hierarchy node.

  ## Parameters
  - `user_id` - User identifier (e.g., email or user ID)
  - `node_ref` - Node reference string (e.g., "C#101" for Company#101)
  - `permission` - One of `:read`, `:write`, `:admin`, or `:blocked`

  ## Examples

      iex> grant_permission("user@example.com", "C#101", :read)
      :ok

      iex> grant_permission("admin@example.com", "P#1", :admin)
      :ok
  """
  def grant_permission(user_id, node_ref, permission)
      when permission in [:read, :write, :admin, :blocked] do
    HierarchyValkeyImpl.grant_permission(user_id, node_ref, permission)
  end

  @doc """
  Revokes a user's permission on a specific hierarchy node.

  ## Examples

      iex> revoke_permission("user@example.com", "C#101")
      :ok
  """
  def revoke_permission(user_id, node_ref) do
    HierarchyValkeyImpl.revoke_permission(user_id, node_ref)
  end

  @doc """
  Gets a user's permission on a specific node.

  Returns `{:ok, permission}` or `{:ok, nil}` if no permission exists.

  ## Examples

      iex> get_permission("user@example.com", "C#101")
      {:ok, :read}

      iex> get_permission("user@example.com", "C#999")
      {:ok, nil}
  """
  def get_permission(user_id, node_ref) do
    HierarchyValkeyImpl.get_permission(user_id, node_ref)
  end

  @doc """
  Gets all permissions for a user across all nodes.

  Returns a list of `%{node_ref: ref, permission: perm}` maps.

  ## Examples

      iex> get_user_permissions("user@example.com")
      {:ok, [
        %{node_ref: "C#101", permission: :read},
        %{node_ref: "P#1", permission: :write}
      ]}
  """
  def get_user_permissions(user_id) do
    HierarchyValkeyImpl.get_user_permissions(user_id)
  end

  @doc """
  Gets the starting hierarchy nodes for a user based on their permissions.

  Returns nodes where the user has direct permissions (entry points into hierarchy).
  Excludes nodes where user has `:blocked` permission.

  ## Examples

      iex> get_start_nodes_for_user("user@example.com")
      {:ok, [
        %{node: %HierarchyNode{...}, permission: :read}
      ]}
  """
  def get_start_nodes_for_user(user_id) do
    HierarchyValkeyImpl.get_start_nodes_for_user(user_id)
  end

  @doc """
  Checks if a user can access a specific node.

  A user can access a node if:
  1. They have a non-blocked permission directly on the node, OR
  2. They have a non-blocked permission on any ancestor of the node

  ## Examples

      iex> can_access_node?("user@example.com", "B#3001")
      true
  """
  def can_access_node?(user_id, node_ref) do
    case get_permission(user_id, node_ref) do
      {:ok, perm} when perm in [:read, :write, :admin] -> true
      {:ok, :blocked} -> false
      {:ok, nil} -> has_ancestor_permission?(user_id, node_ref)
      _ -> false
    end
  end

  defp has_ancestor_permission?(user_id, node_ref) do
    [type_str, id_str] = String.split(node_ref, "#", parts: 2)
    id = String.to_integer(id_str)

    case HierarchyValkeyImpl.get_ancestors(type_str, id) do
      {:ok, ancestors} -> Enum.any?(ancestors, &has_access_permission?(user_id, &1.ref))
      _ -> false
    end
  end

  defp has_access_permission?(user_id, node_ref) do
    match?({:ok, perm} when perm in [:read, :write, :admin], get_permission(user_id, node_ref))
  end

  @doc """
  Blocks a hierarchy node, preventing access.

  ## Examples

      iex> block_node("Company", 101)
      {:ok, %HierarchyNode{blocked: true, ...}}
  """
  def block_node(type, id) do
    with {:ok, node} <- HierarchyValkeyImpl.get(type, id),
         {:ok, blocked_node} <- HierarchyNode.block(node),
         :ok <- HierarchyValkeyImpl.create(blocked_node) do
      {:ok, blocked_node}
    end
  end

  @doc """
  Unblocks a hierarchy node, restoring access.

  ## Examples

      iex> unblock_node("Company", 101)
      {:ok, %HierarchyNode{blocked: false, ...}}
  """
  def unblock_node(type, id) do
    with {:ok, node} <- HierarchyValkeyImpl.get(type, id),
         {:ok, unblocked_node} <- HierarchyNode.unblock(node),
         :ok <- HierarchyValkeyImpl.create(unblocked_node) do
      {:ok, unblocked_node}
    end
  end
end
