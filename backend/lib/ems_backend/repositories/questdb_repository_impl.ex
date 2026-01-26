defmodule EmsBackend.Repositories.QuestDBRepositoryImpl do
  @moduledoc """
  QuestDB implementation supporting multiple protocols:
  - PostgreSQL wire protocol (Postgrex) for SQL queries
  - HTTP REST API for flexible operations
  - InfluxDB Line Protocol (ILP) for high-performance inserts
  """

  @behaviour EmsBackend.Repositories.QuestDBRepository

  # PostgreSQL wire protocol (port 8812 by default)
  @impl true
  def query(sql, params \\ []) do
    case Postgrex.query(:questdb, sql, params) do
      {:ok, %Postgrex.Result{rows: rows, columns: columns}} ->
        result = Enum.map(rows, fn row ->
          columns
          |> Enum.zip(row)
          |> Map.new()
        end)
        {:ok, result}

      {:error, %Postgrex.Error{} = error} ->
        {:error, error.message}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def insert(table, data) do
    # Use HTTP REST API for single inserts
    insert_via_http(table, [data])
  end

  @impl true
  def bulk_insert(table, data) do
    # Use InfluxDB Line Protocol for bulk inserts (high performance)
    insert_via_ilp(table, data)
  end

  # HTTP REST API (port 9000 by default)
  defp insert_via_http(table, data) do
    base_url = questdb_http_url()

    # Build SQL INSERT statement
    columns = data |> List.first() |> Map.keys()
    column_names = Enum.join(columns, ", ")

    values = Enum.map(data, fn row ->
      row_values = Enum.map(columns, fn col -> format_value(Map.get(row, col)) end)
      "(#{Enum.join(row_values, ", ")})"
    end)

    sql = "INSERT INTO #{table} (#{column_names}) VALUES #{Enum.join(values, ", ")}"

    case Req.post("#{base_url}/exec", body: %{query: sql}) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status, body: body}} -> {:error, "HTTP #{status}: #{inspect(body)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  # InfluxDB Line Protocol (port 9009 by default)
  defp insert_via_ilp(table, data) do
    {host, port} = questdb_ilp_config()

    # Convert data to ILP format
    lines = Enum.map(data, fn row ->
      to_ilp_line(table, row)
    end)

    payload = Enum.join(lines, "\n")

    case :gen_tcp.connect(String.to_charlist(host), port, [:binary, active: false]) do
      {:ok, socket} ->
        result = :gen_tcp.send(socket, payload)
        :gen_tcp.close(socket)

        case result do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Convert map to InfluxDB Line Protocol format
  # Format: table_name,tag1=value1,tag2=value2 field1=value1,field2=value2 timestamp
  defp to_ilp_line(table, data) do
    # Extract timestamp if present
    {timestamp, fields} = Map.pop(data, :timestamp)
    {timestamp, fields} = if timestamp, do: {timestamp, fields}, else: Map.pop(fields, "timestamp")

    # For now, treat all fields as fields (not tags)
    # You can customize this based on your data model
    field_str = fields
    |> Enum.map(fn {k, v} -> "#{k}=#{format_ilp_value(v)}" end)
    |> Enum.join(",")

    timestamp_str = if timestamp, do: " #{timestamp}", else: ""

    "#{table} #{field_str}#{timestamp_str}"
  end

  defp format_ilp_value(value) when is_binary(value), do: "\"#{value}\""
  defp format_ilp_value(value) when is_number(value), do: value
  defp format_ilp_value(value) when is_boolean(value), do: if(value, do: "t", else: "f")
  defp format_ilp_value(nil), do: "\"\""
  defp format_ilp_value(value), do: "\"#{inspect(value)}\""

  defp format_value(value) when is_binary(value), do: "'#{String.replace(value, "'", "''")}'"
  defp format_value(value) when is_number(value), do: value
  defp format_value(value) when is_boolean(value), do: value
  defp format_value(nil), do: "NULL"
  defp format_value(value), do: "'#{inspect(value)}'"

  defp questdb_http_url do
    host = System.get_env("QUESTDB_HTTP_HOST") || Application.get_env(:ems_backend, :questdb_http_host) || "localhost"
    port = System.get_env("QUESTDB_HTTP_PORT") || Application.get_env(:ems_backend, :questdb_http_port) || 9000
    "http://#{host}:#{port}"
  end

  defp questdb_ilp_config do
    host = System.get_env("QUESTDB_ILP_HOST") || Application.get_env(:ems_backend, :questdb_ilp_host) || "localhost"
    port = case System.get_env("QUESTDB_ILP_PORT") do
      nil -> Application.get_env(:ems_backend, :questdb_ilp_port) || 9009
      port_str -> String.to_integer(port_str)
    end
    {host, port}
  end
end
