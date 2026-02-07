defmodule EmsBackendWeb.Helpers.HierarchyHtml do
  @moduledoc """
  HTML helpers for generating HTMX-compatible hierarchy responses.

  Generates HTML fragments for the hierarchy tree, node details, and form options.
  """

  alias EmsBackend.Domain.HierarchyNode

  # Icon constants matching the Rust implementation
  @root_icon "🏠"
  @partner_icon "🏢"
  @company_icon "🏢"
  @property_icon "🏘️"
  @building_icon "🏗️"
  @area_icon "📍"
  @group_icon "📁"

  @doc """
  Gets the icon for a node type.
  """
  def get_icon(:root), do: @root_icon
  def get_icon(:partner), do: @partner_icon
  def get_icon(:company), do: @company_icon
  def get_icon(:property), do: @property_icon
  def get_icon(:building), do: @building_icon
  def get_icon(:area), do: @area_icon
  def get_icon(:group), do: @group_icon
  def get_icon(type) when is_binary(type), do: get_icon(String.to_existing_atom(type))
  def get_icon(_), do: "📄"

  @doc """
  Generates an <li> element for a hierarchy node.
  This matches the format expected by the frontend HTMX handlers.
  """
  def generate_li_element(node_ref, node_type, user, node_name, parent_path, with_permissions, api_base_url \\ "") do
    icon = get_icon(node_type)
    has_children = node_type in [:root, :partner, :company, :property, :building]

    # Build the new path including this node
    new_path =
      case parent_path do
        nil -> node_ref
        "" -> node_ref
        path -> "#{path}##{node_ref}"
      end

    children_trigger =
      if has_children do
        ~s(hx-get="#{api_base_url}/hierarchy/query/nodes" ) <>
          ~s(hx-vals='{"id": "#{node_ref}", "user": "#{user}", "path": "#{new_path}", "permissions": "#{with_permissions}"}' ) <>
          ~s(hx-trigger="click once" ) <>
          ~s(hx-target="find .nested-list" ) <>
          ~s(hx-swap="innerHTML" ) <>
          ~s(hx-request='{"noHeaders": true}')
      else
        ""
      end

    permission_checkbox =
      if with_permissions do
        ~s(<input type="checkbox" name="data.allowed" value="#{node_ref}" class="mr-2" />)
      else
        ""
      end

    click_handler =
      if not with_permissions do
        "onclick=\"sessionStorage.setItem('selectedNodeId', '#{node_ref}'); " <>
          "sessionStorage.setItem('selectedNodePath', '#{new_path}'); " <>
          "window.dispatchEvent(new CustomEvent('node-selected'));\""
      else
        ""
      end

    nested_list =
      if has_children do
        ~s(<ul class="nested-list ml-4 hidden"></ul>)
      else
        ""
      end

    toggle_script =
      if has_children do
        ~s(_="on click toggle .hidden on the next <ul/>")
      else
        ""
      end

    """
    <li class="py-1 cursor-pointer hover:bg-gray-100 rounded px-2"
        #{children_trigger}
        #{toggle_script}
        #{click_handler}>
      #{permission_checkbox}
      <span class="mr-1">#{icon}</span>
      <span>#{html_escape(node_name)}</span>
      #{nested_list}
    </li>
    """
  end

  @doc """
  Generates HTML for a list of hierarchy nodes.
  """
  def generate_nodes_html(nodes, user, parent_path, with_permissions, api_base_url \\ "") do
    nodes
    |> Enum.map(fn node ->
      node_ref = get_node_ref(node)
      generate_li_element(
        node_ref,
        get_node_type(node),
        user,
        get_node_name(node),
        parent_path,
        with_permissions,
        api_base_url
      )
    end)
    |> Enum.join("")
  end

  @doc """
  Generates the node detail HTML (similar to node.html template in Rust).
  """
  def generate_node_detail_html(%HierarchyNode{} = node, parent_path) do
    """
    <div class="max-w-3xl mx-auto p-6 bg-white rounded-lg shadow-md my-8">
      <div class="mb-4">
        <label for="id" class="block font-semibold mb-1 text-gray-700">ID:</label>
        <input type="text" id="id" value="#{node.id}" readonly class="w-full px-3 py-2 border border-gray-300 rounded-md bg-gray-50">
      </div>
      <div class="mb-4">
        <label for="name" class="block font-semibold mb-1 text-gray-700">Name:</label>
        <input type="text" id="name" value="#{html_escape(node.name)}" readonly class="w-full px-3 py-2 border border-gray-300 rounded-md bg-gray-50">
      </div>

      <div class="mt-8 pt-6 border-t border-gray-200">
        <h2 class="text-xl font-semibold text-gray-700 mb-4">Metadata</h2>
        #{generate_metadata_html(node)}
        #{generate_sensors_section(node, parent_path)}
      </div>
    </div>
    """
  end

  defp generate_metadata_html(%HierarchyNode{metadata: nil}) do
    ~s(<div class="mb-4"><label class="block font-semibold">No metadata available</label></div>)
  end

  defp generate_metadata_html(%HierarchyNode{type: :company, metadata: metadata}) do
    """
    <div class="mb-4">
      <label for="metaType" class="block font-semibold mb-1 text-gray-700">Metadata Type:</label>
      <input type="text" id="metaType" value="Company" readonly class="w-full px-3 py-2 border border-gray-300 rounded-md bg-gray-50">
    </div>
    #{generate_field("Email", metadata[:email])}
    #{generate_address_section(metadata[:address])}
    """
  end

  defp generate_metadata_html(%HierarchyNode{type: :building, metadata: metadata}) do
    location = metadata[:location] || %{}
    """
    <div class="mb-4">
      <label for="metaType" class="block font-semibold mb-1 text-gray-700">Metadata Type:</label>
      <input type="text" id="metaType" value="Building" readonly class="w-full px-3 py-2 border border-gray-300 rounded-md bg-gray-50">
    </div>
    #{generate_field("Email", metadata[:email])}
    #{generate_field("Latitude", location[:lat])}
    #{generate_field("Longitude", location[:long])}
    """
  end

  defp generate_metadata_html(%HierarchyNode{type: :property, metadata: metadata}) do
    location = metadata[:location] || %{}
    """
    <div class="mb-4">
      <label for="metaType" class="block font-semibold mb-1 text-gray-700">Metadata Type:</label>
      <input type="text" id="metaType" value="Property" readonly class="w-full px-3 py-2 border border-gray-300 rounded-md bg-gray-50">
    </div>
    #{generate_field("Latitude", location[:lat])}
    #{generate_field("Longitude", location[:long])}
    #{generate_address_section(metadata[:address])}
    """
  end

  defp generate_metadata_html(%HierarchyNode{type: :partner, metadata: metadata}) do
    """
    <div class="mb-4">
      <label for="metaType" class="block font-semibold mb-1 text-gray-700">Metadata Type:</label>
      <input type="text" id="metaType" value="Partner" readonly class="w-full px-3 py-2 border border-gray-300 rounded-md bg-gray-50">
    </div>
    #{generate_field("Email", metadata[:email])}
    #{generate_address_section(metadata[:address])}
    """
  end

  defp generate_metadata_html(%HierarchyNode{type: :area}) do
    """
    <div class="mb-4">
      <label for="metaType" class="block font-semibold mb-1 text-gray-700">Metadata Type:</label>
      <input type="text" id="metaType" value="Area" readonly class="w-full px-3 py-2 border border-gray-300 rounded-md bg-gray-50">
    </div>
    """
  end

  defp generate_metadata_html(%HierarchyNode{type: :group}) do
    """
    <div class="mb-4">
      <label for="metaType" class="block font-semibold mb-1 text-gray-700">Metadata Type:</label>
      <input type="text" id="metaType" value="Group" readonly class="w-full px-3 py-2 border border-gray-300 rounded-md bg-gray-50">
    </div>
    """
  end

  defp generate_metadata_html(_) do
    ~s(<div class="mb-4"><label class="block font-semibold">Unknown metadata type</label></div>)
  end

  defp generate_field(_label, nil), do: ""

  defp generate_field(label, value) do
    """
    <div class="mb-4">
      <label class="block font-semibold mb-1 text-gray-700">#{label}:</label>
      <input type="text" value="#{html_escape(to_string(value))}" readonly class="w-full px-3 py-2 border border-gray-300 rounded-md bg-gray-50">
    </div>
    """
  end

  defp generate_address_section(nil), do: ""

  defp generate_address_section(address) when is_map(address) do
    """
    <div class="mt-6 pt-4 border-t border-gray-200">
      <h3 class="text-lg font-medium text-gray-700 mb-3">Address</h3>
      #{generate_field("Country", address[:country])}
      #{generate_field("Street", address[:street])}
      #{generate_field("House Number", address[:nr])}
      #{generate_field("ZIP Code", address[:zip])}
    </div>
    """
  end

  defp generate_sensors_section(%HierarchyNode{type: type}, parent_path)
       when type in [:building, :property, :company, :area] do
    """
    <div class="mb-4">
      <div class="grid grid-cols-[1fr_auto] items-center mb-4">
        <h2 class="text-xl font-semibold text-gray-700">
          Sensors
          <span id="loading-indicator" class="htmx-indicator text-sm text-blue-500 ml-2" style="display: none;">Loading...</span>
        </h2>
        <button _="on click call #add-sensor-dialog.showModal()" class="btn-primary">Tilføj sensor</button>
      </div>

      <ul id="sensor-list"
          class="space-y-2"
          hx-get="/hierarchy/query/sensors"
          hx-vals='{"nodepath": "#{parent_path}"}'
          hx-trigger="load"
          hx-target="#sensor-list"
          hx-swap="innerHTML"
          hx-request='{"noHeaders": true}'
          hx-indicator="#loading-indicator">
        <li class="text-gray-500">Loading sensors...</li>
      </ul>
    </div>
    """
  end

  defp generate_sensors_section(_, _), do: ""

  @doc """
  Generates user table rows HTML.
  """
  def generate_users_table_html([]) do
    ~s(<tr><td colspan="6" class="text-center text-gray-500 py-4">No users found</td></tr>)
  end

  def generate_users_table_html(users) do
    users
    |> Enum.map(fn user ->
      """
      <tr class="hover:bg-gray-50">
        <td class="px-4 py-3 border-b">#{html_escape(user.name)}</td>
        <td class="px-4 py-3 border-b">#{html_escape(user.email)}</td>
        <td class="px-4 py-3 border-b">#{user.profile}</td>
        <td class="px-4 py-3 border-b">#{user.language}</td>
        <td class="px-4 py-3 border-b">#{user.currency}</td>
        <td class="px-4 py-3 border-b">
          <button class="text-red-600 hover:text-red-800 font-bold"
                  onclick="window.dispatchEvent(new CustomEvent('delete-user', { detail: { email: '#{html_escape(user.email)}' } }))">
            Slet
          </button>
        </td>
      </tr>
      """
    end)
    |> Enum.join("")
  end

  @doc """
  Generates sensor list HTML.
  """
  def generate_sensors_html([]) do
    ~s(<li class="text-gray-500">No sensors found</li>)
  end

  def generate_sensors_html(sensors) do
    sensors
    |> Enum.map(fn sensor ->
      ~s(<li class="px-3 py-2 bg-gray-50 rounded border">#{html_escape(sensor)}</li>)
    end)
    |> Enum.join("")
  end

  # Helper to get node reference string
  defp get_node_ref(%HierarchyNode{type: type, id: id}), do: "#{type_to_prefix(type)}##{id}"
  defp get_node_ref(%{ref: ref}), do: ref
  defp get_node_ref(%{type: type, id: id}), do: "#{type_to_prefix(type)}##{id}"

  defp get_node_type(%HierarchyNode{type: type}), do: type
  defp get_node_type(%{type: type}), do: type

  defp get_node_name(%HierarchyNode{name: name}), do: name
  defp get_node_name(%{name: name}), do: name

  defp type_to_prefix(:root), do: "R"
  defp type_to_prefix(:partner), do: "P"
  defp type_to_prefix(:company), do: "C"
  defp type_to_prefix(:property), do: "PR"
  defp type_to_prefix(:building), do: "B"
  defp type_to_prefix(:area), do: "A"
  defp type_to_prefix(:group), do: "G"
  defp type_to_prefix(type) when is_binary(type), do: type

  @doc """
  HTML escapes a string to prevent XSS.
  """
  def html_escape(nil), do: ""

  def html_escape(string) when is_binary(string) do
    string
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  def html_escape(value), do: html_escape(to_string(value))
end
