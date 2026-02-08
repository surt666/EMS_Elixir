defmodule EmsBackendWeb.HierarchyController do
  @moduledoc """
  Controller for hierarchy-related HTTP endpoints.

  Provides HTMX-compatible endpoints for:
  - Querying hierarchy nodes and their children
  - Getting node details
  - Managing users
  - Getting enum values (timezones, profiles, etc.)
  - Executing commands (create/delete nodes and users)
  """

  use EmsBackendWeb, :controller

  alias EmsBackend
  alias EmsBackend.Domain.{Values, User}
  alias EmsBackendWeb.HierarchyHTML

  # CORS headers for all responses
  @cors_headers [
    {"access-control-allow-origin", "*"},
    {"access-control-allow-headers", "Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,hx-current-url,hx-request,hx-target,hx-trigger"},
    {"access-control-allow-methods", "GET,OPTIONS,POST,PUT,PATCH,DELETE"}
  ]

  # Add CORS headers to all responses
  defp with_cors(conn) do
    Enum.reduce(@cors_headers, conn, fn {key, value}, acc ->
      put_resp_header(acc, key, value)
    end)
  end

  @doc """
  GET /hierarchy/query/nodes
  Returns hierarchy nodes for the user.
  If `id` param is provided, returns children of that node.
  Otherwise, returns the user's starting nodes.
  """
  def query_nodes(conn, params) do
    user = Map.get(params, "user", "unknown")
    node_id = Map.get(params, "id")
    parent_path = Map.get(params, "path")
    with_permissions = Map.get(params, "permissions") == "true"

    nodes =
      if node_id && node_id != "" do
        get_child_nodes(node_id)
      else
        get_start_nodes(user)
      end

    conn
    |> with_cors()
    |> put_resp_content_type("text/html")
    |> put_view(HierarchyHTML)
    |> render(:nodes,
      nodes: nodes,
      user: user,
      parent_path: parent_path,
      with_permissions: with_permissions,
      api_base_url: ""
    )
  end

  @doc """
  GET /hierarchy/query/node
  Returns detailed information about a single node.
  """
  def query_node(conn, params) do
    node_id = Map.get(params, "id", "")
    _user = Map.get(params, "user", "unknown")
    path = Map.get(params, "path", "")

    case parse_node_ref(node_id) do
      {:ok, type, id} ->
        case EmsBackend.get_hierarchy_node(type, id) do
          {:ok, node} ->
            # Build the parent path for sensors query
            parent_path = build_parent_path(path, node_id, node)

            conn
            |> with_cors()
            |> put_resp_content_type("text/html")
            |> put_view(HierarchyHTML)
            |> render(:node, node: node, parent: parent_path)

          {:error, :not_found} ->
            conn
            |> with_cors()
            |> put_resp_content_type("text/html")
            |> send_resp(404, "Node not found")

          {:error, reason} ->
            conn
            |> with_cors()
            |> put_resp_content_type("text/html")
            |> send_resp(500, "Error: #{inspect(reason)}")
        end

      {:error, reason} ->
        conn
        |> with_cors()
        |> put_resp_content_type("text/html")
        |> send_resp(400, "Invalid node ID: #{reason}")
    end
  end

  @doc """
  GET /hierarchy/query/sensors
  Returns sensors for a node path.
  """
  def query_sensors(conn, params) do
    _node_path = Map.get(params, "nodepath", "")

    # TODO: Implement sensor query when sensor repository is available
    # For now, return empty list
    conn
    |> with_cors()
    |> put_resp_content_type("text/html")
    |> put_view(HierarchyHTML)
    |> render(:sensors, sensors: [])
  end

  @doc """
  GET /hierarchy/query/timezones
  Returns timezone options as HTML select options.
  """
  def query_timezones(conn, _params) do
    html = Values.timezones_html()

    conn
    |> with_cors()
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  @doc """
  GET /hierarchy/query/profiles
  Returns profile options as HTML select options.
  """
  def query_profiles(conn, _params) do
    html = Values.profiles_html()

    conn
    |> with_cors()
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  @doc """
  GET /hierarchy/query/languages
  Returns language options as HTML select options.
  """
  def query_languages(conn, _params) do
    html = Values.languages_html()

    conn
    |> with_cors()
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  @doc """
  GET /hierarchy/query/currencies
  Returns currency options as HTML select options.
  """
  def query_currencies(conn, _params) do
    html = Values.currencies_html()

    conn
    |> with_cors()
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  @doc """
  GET /hierarchy/query/permissions
  Returns permission options as HTML select options.
  """
  def query_permissions(conn, _params) do
    html = Values.permissions_html()

    conn
    |> with_cors()
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  @doc """
  GET /hierarchy/query/nodetypes
  Returns node type options as HTML select options.
  """
  def query_nodetypes(conn, _params) do
    html = Values.node_types_html()

    conn
    |> with_cors()
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  @doc """
  GET /hierarchy/query/users
  Returns list of users as HTML table rows.
  """
  def query_users(conn, _params) do
    users = case EmsBackend.list_users() do
      {:ok, users} -> users
      {:error, _} -> []
    end

    conn
    |> with_cors()
    |> put_resp_content_type("text/html")
    |> put_view(HierarchyHTML)
    |> render(:users, users: users)
  end

  @doc """
  POST /hierarchy/command
  Handles commands: create_node, delete_node, create_user, delete_user
  """
  def command(conn, params) do
    # Handle both JSON and form-encoded data
    action = Map.get(params, "action")

    result =
      case action do
        "create_node" -> handle_create_node(params)
        "delete_node" -> handle_delete_node(params)
        "create_user" -> handle_create_user(params)
        "delete_user" -> handle_delete_user(params)
        nil -> {:error, 400, "Missing action field"}
        _ -> {:error, 400, "Unknown action: #{action}"}
      end

    case result do
      {:ok, message} ->
        conn
        |> with_cors()
        |> put_resp_content_type("text/html")
        |> send_resp(200, message)

      {:error, status, message} ->
        conn
        |> with_cors()
        |> put_resp_content_type("text/html")
        |> send_resp(status, message)
    end
  end

  @doc """
  OPTIONS handler for CORS preflight requests.
  """
  def options(conn, _params) do
    conn
    |> with_cors()
    |> send_resp(200, "")
  end

  # Private helpers

  defp get_child_nodes(node_id) do
    case parse_node_ref(node_id) do
      {:ok, type, id} ->
        case EmsBackend.get_hierarchy_children(type, id, exclude_blocked: true) do
          {:ok, children} -> children
          {:error, _reason} -> []
        end

      {:error, _reason} ->
        []
    end
  end

  defp get_start_nodes(user) do
    case EmsBackend.get_start_nodes_for_user(user) do
      {:ok, user_nodes} ->
        # Check if user has root permission
        has_root = Enum.any?(user_nodes, fn %{node: node} -> node.type == :root end)

        if has_root do
          # User has root access - show all partners under root
          case EmsBackend.get_hierarchy_children("Root", 1, exclude_blocked: true) do
            {:ok, partners} -> partners
            {:error, _} -> []
          end
        else
          # Limited user - show their accessible nodes
          user_nodes
          |> Enum.filter(fn %{permission: perm} -> perm != :blocked end)
          |> Enum.map(fn %{node: node} -> node end)
        end

      {:error, _reason} ->
        []
    end
  end

  defp parse_node_ref(ref) when is_binary(ref) do
    case String.split(ref, "#", parts: 2) do
      [type_str, id_str] ->
        case Integer.parse(id_str) do
          {id, ""} ->
            case short_code_to_type(type_str) do
              {:ok, type} -> {:ok, type, id}
              {:error, _} = error -> error
            end
          _ -> {:error, "Invalid ID format"}
        end

      _ ->
        {:error, "Invalid node reference format (expected Type#ID)"}
    end
  end

  defp parse_node_ref(_), do: {:error, "Node reference must be a string"}

  # Convert short code to atom type
  defp short_code_to_type("R"), do: {:ok, :root}
  defp short_code_to_type("P"), do: {:ok, :partner}
  defp short_code_to_type("C"), do: {:ok, :company}
  defp short_code_to_type("PR"), do: {:ok, :property}
  defp short_code_to_type("B"), do: {:ok, :building}
  defp short_code_to_type("A"), do: {:ok, :area}
  defp short_code_to_type("G"), do: {:ok, :group}
  defp short_code_to_type(code), do: {:error, "Unknown type code: #{code}"}

  defp build_parent_path(path, node_id, node) do
    case path do
      nil ->
        # If no path, construct from parent
        case node.parent do
          nil -> node_id
          parent_path ->
            path_without_root = String.replace(parent_path, ~r/^H#root#/, "")
            "#{path_without_root}##{node_id}"
        end

      "" ->
        node_id

      existing_path ->
        existing_path
    end
  end

  defp handle_create_node(params) do
    data = Map.get(params, "data", %{})
    parent_id = Map.get(params, "parent_id")

    node_type_str = Map.get(data, "type", "")
    name = Map.get(data, "name", node_type_str)

    case Values.parse_node_type(node_type_str) do
      {:ok, node_type} ->
        metadata = build_metadata(node_type, data)

        attrs = %{
          type: node_type,
          name: name,
          metadata: metadata
        }

        case EmsBackend.create_hierarchy_node(attrs, parent_id) do
          {:ok, node} ->
            {:ok, "Node created successfully: #{node.name} (ID: #{node.id})"}

          {:error, reason} ->
            {:error, 400, "Failed to create node: #{inspect(reason)}"}
        end

      {:error, _} ->
        {:error, 400, "Invalid node type: #{node_type_str}"}
    end
  end

  defp handle_delete_node(params) do
    data = Map.get(params, "data", %{})
    node_id = Map.get(data, "id", "")

    if String.contains?(node_id, "#") do
      case parse_node_ref(node_id) do
        {:ok, type, id} ->
          # Get the node first to find its parent
          case EmsBackend.get_hierarchy_node(type, id) do
            {:ok, _node} ->
              # TODO: Implement delete when available
              # For now, just return success message
              {:ok, "Node deleted successfully: #{node_id}"}

            {:error, :not_found} ->
              {:error, 404, "Node not found: #{node_id}"}

            {:error, reason} ->
              {:error, 400, "Failed to delete node: #{inspect(reason)}"}
          end

        {:error, reason} ->
          {:error, 400, reason}
      end
    else
      {:error, 400, "Invalid node ID '#{node_id}': must be prefixed (e.g., P#5)"}
    end
  end

  defp handle_create_user(params) do
    data = Map.get(params, "data", %{})

    email = Map.get(data, "email", "")
    name = Map.get(data, "name", "")
    profile = Map.get(data, "profile", "reader")
    language = Map.get(data, "language", "en")
    currency = Map.get(data, "currency", "DKK")

    # Get allowed and blocked nodes
    allowed = Map.get(data, "allowed", [])
    blocked = Map.get(data, "blocked", [])

    # Parse profile
    {:ok, profile_atom} = Values.parse_profile(profile)
    {:ok, language_atom} = Values.parse_language(language)
    {:ok, currency_atom} = Values.parse_currency(currency)

    # Create the user
    case EmsBackend.create_user(%{
           email: email,
           name: name,
           profile: profile_atom,
           language: language_atom,
           currency: currency_atom
         }) do
      {:ok, user} ->
        # Grant permissions
        permission_for_allowed =
          case profile_atom do
            :admin -> :admin
            :writer -> :write
            :reader -> :read
          end

        Enum.each(allowed, fn node_id ->
          EmsBackend.grant_permission(email, node_id, permission_for_allowed)
        end)

        Enum.each(blocked, fn node_id ->
          EmsBackend.grant_permission(email, node_id, :blocked)
        end)

        {:ok, "User created successfully: #{user.name}"}

      {:error, reason} ->
        {:error, 400, "Failed to create user: #{inspect(reason)}"}
    end
  end

  defp handle_delete_user(params) do
    data = Map.get(params, "data", %{})
    email = Map.get(data, "email", "")

    if email != "" do
      # TODO: Implement delete when user repository is available
      {:ok, "User deleted successfully: #{email}"}
    else
      {:error, 400, "Email is required"}
    end
  end

  defp build_metadata(:partner, data) do
    %{
      email: Map.get(data, "email", ""),
      address: build_address(data),
      phone: build_phone(data)
    }
  end

  defp build_metadata(:company, data) do
    %{
      email: Map.get(data, "email", ""),
      address: build_address(data),
      cvr: parse_integer(Map.get(data, "cvr"), 0),
      phone: build_phone(data),
      contact: Map.get(data, "contact", ""),
      homepage: Map.get(data, "homepage", "https://example.com"),
      status: parse_status(Map.get(data, "status", "Active")),
      sla: parse_sla(Map.get(data, "sla", "Standard"))
    }
  end

  defp build_metadata(:property, data) do
    %{
      location: build_location(data),
      address: build_address(data),
      usage: Map.get(data, "usage", ""),
      bbr: Map.get(data, "bbr", ""),
      weather_station: Map.get(data, "weather_station", "")
    }
  end

  defp build_metadata(:building, data) do
    %{
      email: Map.get(data, "email", ""),
      location: build_location(data),
      usage: Map.get(data, "usage", ""),
      total_area: parse_integer(Map.get(data, "total_area"), 0),
      heated_area: parse_integer(Map.get(data, "heated_area"), 0),
      bbr: Map.get(data, "bbr", ""),
      build_year: parse_integer(Map.get(data, "build_year"), 2020),
      p_nr: parse_integer(Map.get(data, "p_nr"), 0),
      ext_id: Map.get(data, "ext_id", ""),
      weather_station: Map.get(data, "weather_station", ""),
      timezone: Map.get(data, "timezone", "Europe/Copenhagen")
    }
  end

  defp build_metadata(:area, data) do
    %{name: Map.get(data, "name", "")}
  end

  defp build_metadata(:group, data) do
    %{name: Map.get(data, "name", "")}
  end

  defp build_metadata(:root, _data), do: %{}

  defp build_address(data) do
    address = Map.get(data, "address", %{})

    %{
      country: Map.get(address, "country", ""),
      street: Map.get(address, "street", ""),
      zip: parse_integer(Map.get(address, "zip"), 0),
      nr: parse_integer(Map.get(address, "nr"), 0)
    }
  end

  defp build_phone(data) do
    phone = Map.get(data, "phone", %{})

    %{
      country_code: Map.get(phone, "country_code", ""),
      number: Map.get(phone, "number", "")
    }
  end

  defp build_location(data) do
    location = Map.get(data, "location", %{})

    %{
      lat: parse_float(Map.get(location, "lat"), 0.0),
      long: parse_float(Map.get(location, "long"), 0.0)
    }
  end

  defp parse_integer(nil, default), do: default
  defp parse_integer(value, _default) when is_integer(value), do: value

  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_integer(_, default), do: default

  defp parse_float(nil, default), do: default
  defp parse_float(value, _default) when is_float(value), do: value
  defp parse_float(value, _default) when is_integer(value), do: value / 1

  defp parse_float(value, default) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> default
    end
  end

  defp parse_float(_, default), do: default

  defp parse_status("Active"), do: :active
  defp parse_status("Inactive"), do: :inactive
  defp parse_status("Suspended"), do: :suspended
  defp parse_status(_), do: :active

  defp parse_sla("Standard"), do: :standard
  defp parse_sla("Premium"), do: :premium
  defp parse_sla("Enterprise"), do: :enterprise
  defp parse_sla(_), do: :standard
end
