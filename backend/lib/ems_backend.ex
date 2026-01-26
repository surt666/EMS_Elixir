defmodule EmsBackend do
  @moduledoc """
  EmsBackend context for managing hierarchy nodes.

  This module provides the public API for creating and managing
  organizational hierarchy nodes (Partner, Company, Property, Building, Area, Group).

  Uses HierarchyValkeyImpl as the default repository implementation.
  """

  alias EmsBackend.Domain.HierarchyNode
  alias EmsBackend.Repositories.HierarchyValkeyImpl

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
      {:ok, _root} -> :ok
      {:error, :not_found} ->
        {:ok, root} = HierarchyNode.new(%{id: 1, type: :root, name: "Root", metadata: %{}})
        HierarchyValkeyImpl.create(root)
      _ -> :ok
    end
  end

  defp validate_and_determine_parent(:root, _), do: {:ok, nil}
  defp validate_and_determine_parent(:partner, nil), do: {:ok, "Root#1"}
  defp validate_and_determine_parent(:partner, parent_ref), do: {:ok, parent_ref}
  defp validate_and_determine_parent(type, nil) when type in [:company, :property, :building, :area, :group],
    do: {:error, "Parent is required for #{type} nodes"}
  defp validate_and_determine_parent(_, parent_ref), do: {:ok, parent_ref}

  defp maybe_link_to_parent(_node, nil), do: :ok
  defp maybe_link_to_parent(node, parent_ref) do
    # Parse parent_ref to get type and id
    [parent_type_str, parent_id_str] = String.split(parent_ref, "#")
    parent_id = String.to_integer(parent_id_str)

    case HierarchyValkeyImpl.get(parent_type_str, parent_id) do
      {:ok, parent_node} ->
        HierarchyValkeyImpl.link_child(parent_node, node)
      error -> error
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

  ## Examples

      iex> get_hierarchy_children("Company", 1001)
      {:ok, [%{id: 2001, type: "Property", name: "Building A", ref: "Property#2001"}]}
  """
  def get_hierarchy_children(type, id) do
    HierarchyValkeyImpl.get_children(type, id)
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
end
