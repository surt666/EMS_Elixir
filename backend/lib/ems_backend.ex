defmodule EmsBackend do
  @moduledoc """
  EmsBackend public API.

  This module provides the unified public interface for the EMS backend.
  It delegates to specialized services for different concerns:

  - `EmsBackend.Services.HierarchyService` - Hierarchy node management
  - `EmsBackend.Services.PermissionService` - User permissions

  Future services:
  - `EmsBackend.Services.SensorService` - Sensor data management
  - `EmsBackend.Services.AggregationService` - Data aggregations
  - `EmsBackend.Services.AlarmService` - Alarm management
  - `EmsBackend.Services.SearchService` - Search functionality
  """

  alias EmsBackend.Services.HierarchyService
  alias EmsBackend.Services.PermissionService
  alias EmsBackend.Services.UserService

  # ============================================================================
  # Hierarchy Management
  # ============================================================================

  @doc """
  Creates a new hierarchy node and stores it.

  See `EmsBackend.Services.HierarchyService.create/2` for details.
  """
  defdelegate create_hierarchy_node(attrs, parent_ref \\ nil), to: HierarchyService, as: :create

  @doc """
  Gets a hierarchy node by type and ID.

  See `EmsBackend.Services.HierarchyService.get/2` for details.
  """
  defdelegate get_hierarchy_node(type, id), to: HierarchyService, as: :get

  @doc """
  Links a child node to a parent node in the hierarchy.

  See `EmsBackend.Services.HierarchyService.link/2` for details.
  """
  defdelegate link_hierarchy_nodes(parent_node, child_node), to: HierarchyService, as: :link

  @doc """
  Removes the parent-child relationship between two nodes.

  See `EmsBackend.Services.HierarchyService.unlink/4` for details.
  """
  defdelegate unlink_hierarchy_nodes(parent_type, parent_id, child_type, child_id),
    to: HierarchyService,
    as: :unlink

  @doc """
  Gets all children of a hierarchy node.

  See `EmsBackend.Services.HierarchyService.get_children/3` for details.
  """
  defdelegate get_hierarchy_children(type, id, opts \\ []), to: HierarchyService, as: :get_children

  @doc """
  Gets the parent of a hierarchy node.

  See `EmsBackend.Services.HierarchyService.get_parent/2` for details.
  """
  defdelegate get_hierarchy_parent(type, id), to: HierarchyService, as: :get_parent

  @doc """
  Gets all ancestors of a hierarchy node.

  See `EmsBackend.Services.HierarchyService.get_ancestors/2` for details.
  """
  defdelegate get_hierarchy_ancestors(type, id), to: HierarchyService, as: :get_ancestors

  @doc """
  Gets all descendants of a hierarchy node.

  See `EmsBackend.Services.HierarchyService.get_descendants/2` for details.
  """
  defdelegate get_hierarchy_descendants(type, id), to: HierarchyService, as: :get_descendants

  @doc """
  Gets all descendants of a specific type.

  See `EmsBackend.Services.HierarchyService.get_descendants_by_type/3` for details.
  """
  defdelegate get_hierarchy_descendants_by_type(type, id, descendant_type),
    to: HierarchyService,
    as: :get_descendants_by_type

  @doc """
  Blocks a hierarchy node.

  See `EmsBackend.Services.HierarchyService.block/2` for details.
  """
  defdelegate block_node(type, id), to: HierarchyService, as: :block

  @doc """
  Unblocks a hierarchy node.

  See `EmsBackend.Services.HierarchyService.unblock/2` for details.
  """
  defdelegate unblock_node(type, id), to: HierarchyService, as: :unblock

  # ============================================================================
  # Permission Management
  # ============================================================================

  @doc """
  Grants a permission to a user on a hierarchy node.

  See `EmsBackend.Services.PermissionService.grant/3` for details.
  """
  defdelegate grant_permission(user_id, node_ref, permission), to: PermissionService, as: :grant

  @doc """
  Revokes a user's permission on a hierarchy node.

  See `EmsBackend.Services.PermissionService.revoke/2` for details.
  """
  defdelegate revoke_permission(user_id, node_ref), to: PermissionService, as: :revoke

  @doc """
  Gets a user's permission on a specific node.

  See `EmsBackend.Services.PermissionService.get/2` for details.
  """
  defdelegate get_permission(user_id, node_ref), to: PermissionService, as: :get

  @doc """
  Gets all permissions for a user.

  See `EmsBackend.Services.PermissionService.get_all/1` for details.
  """
  defdelegate get_user_permissions(user_id), to: PermissionService, as: :get_all

  @doc """
  Gets the starting hierarchy nodes for a user.

  See `EmsBackend.Services.PermissionService.get_start_nodes/1` for details.
  """
  defdelegate get_start_nodes_for_user(user_id), to: PermissionService, as: :get_start_nodes

  @doc """
  Checks if a user can access a specific node.

  See `EmsBackend.Services.PermissionService.can_access?/2` for details.
  """
  defdelegate can_access_node?(user_id, node_ref), to: PermissionService, as: :can_access?

  # ============================================================================
  # User Management
  # ============================================================================

  @doc """
  Creates a new user.

  See `EmsBackend.Services.UserService.create/1` for details.
  """
  defdelegate create_user(attrs), to: UserService, as: :create

  @doc """
  Gets a user by email.

  See `EmsBackend.Services.UserService.get/1` for details.
  """
  defdelegate get_user(email), to: UserService, as: :get

  @doc """
  Lists all users.

  See `EmsBackend.Services.UserService.list/0` for details.
  """
  defdelegate list_users(), to: UserService, as: :list

  @doc """
  Deletes a user by email.

  See `EmsBackend.Services.UserService.delete/1` for details.
  """
  defdelegate delete_user(email), to: UserService, as: :delete

  @doc """
  Updates a user.

  See `EmsBackend.Services.UserService.update/2` for details.
  """
  defdelegate update_user(email, attrs), to: UserService, as: :update
end
