defmodule EmsBackend.Services.HierarchyService do
  @moduledoc """
  Service for managing organizational hierarchy nodes.

  Handles creation, linking, and traversal of hierarchy nodes with
  business rule enforcement (e.g., valid parent-child relationships).
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

      iex> create(%{name: "Acme Corp", type: :company, metadata: company_metadata()}, "Partner#1")
      {:ok, %HierarchyNode{type: :company, ...}}

      iex> create(%{name: "My Partner", type: :partner, metadata: partner_metadata()})
      {:ok, %HierarchyNode{type: :partner, parent: "Root#1"}}
  """
  def create(attrs, parent_ref \\ nil) do
    ensure_root_exists()

    with {:ok, actual_parent_ref} <- validate_and_determine_parent(attrs[:type], parent_ref),
         {:ok, node} <- HierarchyNode.new(attrs),
         :ok <- HierarchyValkeyImpl.create(node),
         :ok <- maybe_link_to_parent(node, actual_parent_ref) do
      {:ok, node}
    end
  end

  @doc """
  Gets a hierarchy node by type and ID.

  ## Examples

      iex> get("Company", 1001)
      {:ok, %HierarchyNode{}}

      iex> get("Company", 999)
      {:error, :not_found}
  """
  def get(type, id) do
    HierarchyValkeyImpl.get(type, id)
  end

  @doc """
  Links a child node to a parent node in the hierarchy.

  Creates bidirectional hexastore indices for efficient traversal.

  ## Examples

      iex> link(parent_node, child_node)
      :ok
  """
  def link(parent_node, child_node) do
    HierarchyValkeyImpl.link_child(parent_node, child_node)
  end

  @doc """
  Removes the parent-child relationship between two nodes.

  ## Examples

      iex> unlink("Company", 1001, "Property", 2001)
      :ok
  """
  def unlink(parent_type, parent_id, child_type, child_id) do
    HierarchyValkeyImpl.unlink_child(parent_type, parent_id, child_type, child_id)
  end

  @doc """
  Gets all children of a hierarchy node.

  ## Options
  - `:exclude_blocked` - When true, filters out blocked nodes (default: false)

  ## Examples

      iex> get_children("Company", 1001)
      {:ok, [%{id: 2001, type: "Property", name: "Building A", ref: "Property#2001"}]}
  """
  def get_children(type, id, opts \\ []) do
    with {:ok, children} <- HierarchyValkeyImpl.get_children(type, id) do
      {:ok, maybe_filter_blocked(children, opts[:exclude_blocked])}
    end
  end

  @doc """
  Gets the parent of a hierarchy node.

  ## Examples

      iex> get_parent("Property", 2001)
      {:ok, %{id: 1001, type: "Company", name: "Acme Corp", ref: "Company#1001"}}
  """
  def get_parent(type, id) do
    HierarchyValkeyImpl.get_parent(type, id)
  end

  @doc """
  Gets all ancestors of a hierarchy node (recursive).

  Returns list from immediate parent to root.

  ## Examples

      iex> get_ancestors("Building", 3001)
      {:ok, [
        %{id: 2001, type: "Property", name: "Property A"},
        %{id: 1001, type: "Company", name: "Acme Corp"}
      ]}
  """
  def get_ancestors(type, id) do
    HierarchyValkeyImpl.get_ancestors(type, id)
  end

  @doc """
  Gets all descendants of a hierarchy node (recursive).

  Returns flat list of all children, grandchildren, etc.

  ## Examples

      iex> get_descendants("Company", 1001)
      {:ok, [
        %{id: 2001, type: "Property", name: "Property A"},
        %{id: 3001, type: "Building", name: "Building 1"}
      ]}
  """
  def get_descendants(type, id) do
    HierarchyValkeyImpl.get_descendants(type, id)
  end

  @doc """
  Gets all descendants of a specific type using materialized descendant sets.
  This is O(1) instead of recursive traversal.

  ## Examples

      iex> get_descendants_by_type("Company", 1001, :building)
      {:ok, [
        %{id: 3001, type: :building, ref: "Building#3001"}
      ]}
  """
  def get_descendants_by_type(type, id, descendant_type) do
    HierarchyValkeyImpl.get_descendants_by_type(type, id, descendant_type)
  end

  @doc """
  Blocks a hierarchy node, preventing access.

  ## Examples

      iex> block("Company", 101)
      {:ok, %HierarchyNode{blocked: true, ...}}
  """
  def block(type, id) do
    with {:ok, node} <- HierarchyValkeyImpl.get(type, id),
         {:ok, blocked_node} <- HierarchyNode.block(node),
         :ok <- HierarchyValkeyImpl.create(blocked_node) do
      {:ok, blocked_node}
    end
  end

  @doc """
  Unblocks a hierarchy node, restoring access.

  ## Examples

      iex> unblock("Company", 101)
      {:ok, %HierarchyNode{blocked: false, ...}}
  """
  def unblock(type, id) do
    with {:ok, node} <- HierarchyValkeyImpl.get(type, id),
         {:ok, unblocked_node} <- HierarchyNode.unblock(node),
         :ok <- HierarchyValkeyImpl.create(unblocked_node) do
      {:ok, unblocked_node}
    end
  end

  @doc """
  Returns the allowed parent types for a given child type.

  ## Examples

      iex> allowed_parents(:building)
      [:company, :property, :group]
  """
  def allowed_parents(child_type) do
    Map.get(@allowed_parents, child_type, [])
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
    [parent_type_str, parent_id_str] = String.split(parent_ref, "#")
    parent_id = String.to_integer(parent_id_str)

    case HierarchyValkeyImpl.get(parent_type_str, parent_id) do
      {:ok, parent_node} ->
        HierarchyValkeyImpl.link_child(parent_node, node)

      error ->
        error
    end
  end

  defp maybe_filter_blocked(children, false), do: children
  defp maybe_filter_blocked(children, nil), do: children

  defp maybe_filter_blocked(children, true) do
    Enum.reject(children, fn child ->
      match?({:ok, %{blocked: true}}, HierarchyValkeyImpl.get(child.type, child.id))
    end)
  end
end
