defmodule EmsBackendWeb.HierarchyHTML do
  @moduledoc """
  HTML view module for hierarchy templates.
  """
  use EmsBackendWeb, :html

  embed_templates "hierarchy_html/*"

  @doc """
  Renders a metadata type field.
  """
  attr :type, :string, required: true

  def metadata_type_field(assigns) do
    ~H"""
    <div class="mb-4">
      <label for="metaType" class="block font-semibold mb-1 text-gray-700">Metadata Type:</label>
      <input type="text" id="metaType" value={@type} readonly class="w-full px-3 py-2 border border-gray-300 rounded-md bg-gray-50">
    </div>
    """
  end

  @doc """
  Renders a readonly text field.
  """
  attr :label, :string, required: true
  attr :value, :any, default: nil

  def text_field(assigns) do
    ~H"""
    <%= if @value do %>
      <div class="mb-4">
        <label class="block font-semibold mb-1 text-gray-700"><%= @label %>:</label>
        <input type="text" value={@value} readonly class="w-full px-3 py-2 border border-gray-300 rounded-md bg-gray-50">
      </div>
    <% end %>
    """
  end

  @doc """
  Renders an address section.
  """
  attr :address, :map, default: nil

  def address_section(assigns) do
    ~H"""
    <%= if @address do %>
      <div class="mt-6 pt-4 border-t border-gray-200">
        <h3 class="text-lg font-medium text-gray-700 mb-3">Address</h3>
        <.text_field label="Country" value={@address[:country]} />
        <.text_field label="Street" value={@address[:street]} />
        <.text_field label="House Number" value={@address[:nr]} />
        <.text_field label="ZIP Code" value={@address[:zip]} />
      </div>
    <% end %>
    """
  end

  @doc """
  Renders a hierarchy node list item.
  """
  attr :node_ref, :string, required: true
  attr :node_type, :atom, required: true
  attr :node_name, :string, required: true
  attr :user, :string, required: true
  attr :parent_path, :string, default: nil
  attr :with_permissions, :boolean, default: false
  attr :api_base_url, :string, default: ""

  def node_item(assigns) do
    icon = get_icon(assigns.node_type)
    is_building = assigns.node_type == :building
    has_children = not is_building

    new_path =
      case assigns.parent_path do
        nil -> assigns.node_ref
        "" -> assigns.node_ref
        path -> "#{path}##{assigns.node_ref}"
      end

    display_name = if assigns.node_name == "root", do: "", else: assigns.node_name

    assigns =
      assigns
      |> assign(:icon, icon)
      |> assign(:has_children, has_children)
      |> assign(:new_path, new_path)
      |> assign(:display_name, display_name)

    ~H"""
    <li data-id={@node_ref} data-path={@new_path}>
      <div
        class="icon-wrapper"
        {if @has_children, do: htmx_attrs_for_children(@node_ref, @user, @new_path, @api_base_url), else: %{}}
        {if @has_children, do: %{"_" => "on click toggle .hidden on next .nested-list then toggle .rotate-90 on first .navigation-item__arrow in me"}, else: %{}}
      >
        <%= if @has_children do %>
          <svg aria-hidden="true" focusable="false" class="navigation-item__arrow navigation-item__icon" width="16" height="16">
            <use href="#chevron-right"></use>
          </svg>
        <% end %>
      </div>
      <%= @icon %>
      <%= unless @with_permissions do %>
        <a
          href="#"
          class="node-name-link"
          data-node-id={@node_ref}
          data-node-path={@parent_path || ""}
          hx-get={"#{@api_base_url}/hierarchy/query/node?id=#{URI.encode_www_form(@node_ref)}&user=#{@user}"}
          hx-request='{"noHeaders": true}'
          hx-target=".main-area"
          hx-swap="innerHTML"
          _="on click remove .selected from .node-name-link in body then add .selected to me then set sessionStorage.selectedNodeId to my @data-node-id then set sessionStorage.selectedNodePath to my @data-node-path"
          style="cursor: pointer; text-decoration: none; color: inherit;"
        >
          <%= @display_name %>
        </a>
      <% else %>
        <input type="checkbox" name="data.allowed" value={@node_ref} class="mr-2" />
        <span><%= @display_name %></span>
      <% end %>
      <ul class="nested-list hidden"></ul>
    </li>
    """
  end

  defp htmx_attrs_for_children(node_ref, user, new_path, api_base_url) do
    %{
      "hx-get" => "#{api_base_url}/hierarchy/query/nodes?id=#{URI.encode_www_form(node_ref)}&user=#{user}&path=#{URI.encode_www_form(new_path)}",
      "hx-request" => ~s({"noHeaders": true}),
      "hx-target" => "next .nested-list",
      "hx-trigger" => "click,loadChildren"
    }
  end

  defp htmx_attrs(node_ref, user, new_path, with_permissions, api_base_url) do
    %{
      "hx-get" => "#{api_base_url}/hierarchy/query/nodes",
      "hx-vals" => Jason.encode!(%{id: node_ref, user: user, path: new_path, permissions: to_string(with_permissions)}),
      "hx-trigger" => "click once",
      "hx-target" => "find .nested-list",
      "hx-swap" => "innerHTML",
      "hx-request" => ~s({"noHeaders": true})
    }
  end


  # Icon constants
  defp get_icon(:root), do: "🏠"
  defp get_icon(:partner), do: "🏢"
  defp get_icon(:company), do: "🏢"
  defp get_icon(:property), do: "🏘️"
  defp get_icon(:building), do: "🏗️"
  defp get_icon(:area), do: "📍"
  defp get_icon(:group), do: "📁"
  defp get_icon(_), do: "📄"

  @doc """
  Gets the node reference string (e.g., "C#123" for company with id 123).
  """
  def get_node_ref(%{type: type, id: id}) do
    "#{type_to_prefix(type)}##{id}"
  end

  defp type_to_prefix(:root), do: "R"
  defp type_to_prefix(:partner), do: "P"
  defp type_to_prefix(:company), do: "C"
  defp type_to_prefix(:property), do: "PR"
  defp type_to_prefix(:building), do: "B"
  defp type_to_prefix(:area), do: "A"
  defp type_to_prefix(:group), do: "G"
  defp type_to_prefix(type) when is_binary(type), do: type
end
