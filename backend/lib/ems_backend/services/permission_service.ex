defmodule EmsBackend.Services.PermissionService do
  @moduledoc """
  Service for managing user permissions on hierarchy nodes.

  Handles granting, revoking, and checking permissions with
  support for permission inheritance through the hierarchy.
  """

  alias EmsBackend.Repositories.HierarchyValkeyImpl

  @type permission :: :read | :write | :admin | :blocked

  @doc """
  Grants a permission to a user on a specific hierarchy node.

  ## Parameters
  - `user_id` - User identifier (e.g., email or user ID)
  - `node_ref` - Node reference string (e.g., "C#101" for Company#101)
  - `permission` - One of `:read`, `:write`, `:admin`, or `:blocked`

  ## Examples

      iex> grant("user@example.com", "C#101", :read)
      :ok

      iex> grant("admin@example.com", "P#1", :admin)
      :ok
  """
  def grant(user_id, node_ref, permission)
      when permission in [:read, :write, :admin, :blocked] do
    HierarchyValkeyImpl.grant_permission(user_id, node_ref, permission)
  end

  @doc """
  Revokes a user's permission on a specific hierarchy node.

  ## Examples

      iex> revoke("user@example.com", "C#101")
      :ok
  """
  def revoke(user_id, node_ref) do
    HierarchyValkeyImpl.revoke_permission(user_id, node_ref)
  end

  @doc """
  Gets a user's permission on a specific node.

  Returns `{:ok, permission}` or `{:ok, nil}` if no permission exists.

  ## Examples

      iex> get("user@example.com", "C#101")
      {:ok, :read}

      iex> get("user@example.com", "C#999")
      {:ok, nil}
  """
  def get(user_id, node_ref) do
    HierarchyValkeyImpl.get_permission(user_id, node_ref)
  end

  @doc """
  Gets all permissions for a user across all nodes.

  Returns a list of `%{node_ref: ref, permission: perm}` maps.

  ## Examples

      iex> get_all("user@example.com")
      {:ok, [
        %{node_ref: "C#101", permission: :read},
        %{node_ref: "P#1", permission: :write}
      ]}
  """
  def get_all(user_id) do
    HierarchyValkeyImpl.get_user_permissions(user_id)
  end

  @doc """
  Gets the starting hierarchy nodes for a user based on their permissions.

  Returns nodes where the user has direct permissions (entry points into hierarchy).
  Excludes nodes where user has `:blocked` permission.

  ## Examples

      iex> get_start_nodes("user@example.com")
      {:ok, [
        %{node: %HierarchyNode{...}, permission: :read}
      ]}
  """
  def get_start_nodes(user_id) do
    HierarchyValkeyImpl.get_start_nodes_for_user(user_id)
  end

  @doc """
  Checks if a user can access a specific node.

  A user can access a node if:
  1. They have a non-blocked permission directly on the node, OR
  2. They have a non-blocked permission on any ancestor of the node

  ## Examples

      iex> can_access?("user@example.com", "B#3001")
      true
  """
  def can_access?(user_id, node_ref) do
    case get(user_id, node_ref) do
      {:ok, perm} when perm in [:read, :write, :admin] -> true
      {:ok, :blocked} -> false
      {:ok, nil} -> has_ancestor_permission?(user_id, node_ref)
      _ -> false
    end
  end

  @doc """
  Gets the effective permission for a user on a node.

  Checks direct permission first, then walks up the hierarchy
  to find inherited permissions.

  Returns `{:ok, permission}` or `{:ok, nil}` if no access.

  ## Examples

      iex> effective_permission("user@example.com", "B#3001")
      {:ok, :read}
  """
  def effective_permission(user_id, node_ref) do
    case get(user_id, node_ref) do
      {:ok, :blocked} -> {:ok, :blocked}
      {:ok, nil} -> find_ancestor_permission(user_id, node_ref)
      result -> result
    end
  end

  # Private helpers

  defp has_ancestor_permission?(user_id, node_ref) do
    [type_str, id_str] = String.split(node_ref, "#", parts: 2)
    id = String.to_integer(id_str)

    case HierarchyValkeyImpl.get_ancestors(type_str, id) do
      {:ok, ancestors} -> Enum.any?(ancestors, &has_access_permission?(user_id, &1.ref))
      _ -> false
    end
  end

  defp find_ancestor_permission(user_id, node_ref) do
    [type_str, id_str] = String.split(node_ref, "#", parts: 2)
    id = String.to_integer(id_str)

    case HierarchyValkeyImpl.get_ancestors(type_str, id) do
      {:ok, ancestors} ->
        perm = Enum.find_value(ancestors, fn ancestor ->
          case get(user_id, ancestor.ref) do
            {:ok, p} when p in [:read, :write, :admin] -> p
            _ -> nil
          end
        end)
        {:ok, perm}

      _ ->
        {:ok, nil}
    end
  end

  defp has_access_permission?(user_id, node_ref) do
    match?({:ok, perm} when perm in [:read, :write, :admin], get(user_id, node_ref))
  end
end
