defmodule EmsBackend.Repositories.HierarchyRepository do
  @moduledoc """
  Repository behavior for managing hierarchy nodes and relationships.

  This defines the interface for storing and querying organizational hierarchies.
  Implementations handle their own storage details (e.g., ValkeyImpl uses hexastore pattern).
  """

  alias EmsBackend.Domain.HierarchyNode

  @type node_type :: HierarchyNode.node_type()
  @type node_id :: non_neg_integer()
  @type node_ref :: %{
          id: node_id(),
          type: node_type(),
          name: String.t(),
          ref: String.t()
        }

  @doc """
  Stores a hierarchy node.
  """
  @callback create(node :: HierarchyNode.t()) :: :ok | {:error, term()}

  @doc """
  Retrieves a hierarchy node by type and ID.
  """
  @callback get(type :: node_type() | String.t(), id :: node_id()) ::
              {:ok, HierarchyNode.t()} | {:error, :not_found} | {:error, term()}

  @doc """
  Creates a parent-child relationship between two nodes.
  """
  @callback link_child(parent :: HierarchyNode.t(), child :: HierarchyNode.t()) ::
              :ok | {:error, term()}

  @doc """
  Gets all children of a node.
  """
  @callback get_children(type :: node_type() | String.t(), id :: node_id()) ::
              {:ok, [node_ref()]} | {:error, term()}

  @doc """
  Gets the parent of a node.
  Returns nil if the node has no parent.
  """
  @callback get_parent(type :: node_type() | String.t(), id :: node_id()) ::
              {:ok, node_ref() | nil} | {:error, term()}

  @doc """
  Gets all ancestors of a node (recursive, from parent to root).
  """
  @callback get_ancestors(type :: node_type() | String.t(), id :: node_id()) ::
              {:ok, [node_ref()]} | {:error, term()}

  @doc """
  Gets all descendants of a node (recursive, all children and their children).
  """
  @callback get_descendants(type :: node_type() | String.t(), id :: node_id()) ::
              {:ok, [node_ref()]} | {:error, term()}

  @doc """
  Gets all descendants of a specific type using materialized descendant sets.
  This is O(1) instead of recursive traversal.

  For example, to get all buildings under a company:
  get_descendants_by_type("Company", 101, :building)
  """
  @callback get_descendants_by_type(
              type :: node_type() | String.t(),
              id :: node_id(),
              descendant_type :: node_type()
            ) :: {:ok, [node_ref()]} | {:error, term()}

  @doc """
  Removes a parent-child relationship.
  """
  @callback unlink_child(
              parent_type :: node_type() | String.t(),
              parent_id :: node_id(),
              child_type :: node_type() | String.t(),
              child_id :: node_id()
            ) :: :ok | {:error, term()}
end
