defmodule Mix.Tasks.GenerateHierarchy do
  @moduledoc """
  Generates sample hierarchy data in Valkey/Redis.

  Usage:
    mix generate_hierarchy [--buildings-per-property N]

  Options:
    --buildings-per-property  Number of buildings per property (default: 10)

  This script generates:
  - 1 root node
  - 5 partners under root
  - 20 companies per partner
  - 50 properties per company
  - N buildings per property (configurable)
  - 2 sensors per building (not yet implemented - will be added with sensor module)

  It also creates:
  - 2 test users with permissions
  - Proper parent-child relationships
  - ID counters for each node type
  """

  use Mix.Task

  alias EmsBackend.Domain.HierarchyNode
  alias EmsBackend.Repositories.HierarchyValkeyImpl, as: Repo

  @shortdoc "Generates sample hierarchy data in Valkey"

  @impl Mix.Task
  def run(args) do
    # Parse command line options
    {opts, _, _} = OptionParser.parse(args,
      switches: [buildings_per_property: :integer],
      aliases: [b: :buildings_per_property]
    )

    buildings_per_property = Keyword.get(opts, :buildings_per_property, 10)

    # Start the application
    Mix.Task.run("app.start")

    IO.puts("Starting hierarchy data generation...")
    IO.puts("Buildings per property: #{buildings_per_property}")
    IO.puts("")

    # Initialize counters
    initialize_counters()

    # Generate and store data
    total_items = generate_data(buildings_per_property)

    IO.puts("")
    IO.puts("Data generation complete! #{total_items} items were created.")
  end

  defp initialize_counters do
    IO.puts("Initializing ID counters...")

    counters = [
      {"counter:P", 1000},
      {"counter:C", 1000},
      {"counter:PR", 1000},
      {"counter:B", 1000},
      {"counter:S", 1000}
    ]

    Enum.each(counters, fn {key, initial_value} ->
      # Only set if doesn't exist
      case Redix.command(:redix, ["SET", key, initial_value, "NX"]) do
        {:ok, "OK"} -> IO.puts("  #{key} initialized to #{initial_value}")
        {:ok, nil} -> IO.puts("  #{key} already exists, skipping")
        {:error, reason} -> IO.puts("  Error initializing #{key}: #{inspect(reason)}")
      end
    end)
  end

  defp generate_data(buildings_per_property) do
    timestamp = DateTime.utc_now()
    total_items = 0

    # Create root node
    IO.puts("Creating root node...")
    {:ok, root_node} = create_root_node(timestamp)
    total_items = total_items + 1

    # Create test users
    IO.puts("Creating test users...")
    create_test_users(timestamp)
    total_items = total_items + 2

    # Grant root admin permission to admin user
    Repo.grant_permission("stel@energidata.dk", "R#1", :admin)
    total_items = total_items + 1

    # Generate partners
    IO.puts("Generating hierarchy structure...")
    {partner_total, _company_map} = generate_partners(root_node, timestamp, buildings_per_property)
    total_items = total_items + partner_total

    total_items
  end

  defp create_root_node(timestamp) do
    {:ok, node} = HierarchyNode.new(%{
      id: 1,
      type: :root,
      name: "Root",
      metadata: %{},
      created: timestamp,
      parent: nil
    })

    :ok = Repo.create(node)
    {:ok, node}
  end

  defp create_test_users(_timestamp) do
    alias EmsBackend.Services.UserService

    # Create admin user
    case UserService.create(%{
      email: "stel@energidata.dk",
      name: "Stel Admin",
      profile: :admin,
      language: :danish,
      currency: :dkk
    }) do
      {:ok, _} -> IO.puts("  - stel@energidata.dk (admin with root access)")
      {:error, _} -> IO.puts("  - stel@energidata.dk already exists or error")
    end

    # Create limited user
    case UserService.create(%{
      email: "stel@enity.io",
      name: "Stel Limited",
      profile: :reader,
      language: :english,
      currency: :dkk
    }) do
      {:ok, _} -> IO.puts("  - stel@enity.io (limited access)")
      {:error, _} -> IO.puts("  - stel@enity.io already exists or error")
    end
  end

  defp generate_partners(root_node, timestamp, buildings_per_property) do
    total_items = 0
    company_map = %{}

    Enum.reduce(1..5, {total_items, company_map}, fn p, {acc_total, acc_companies} ->
      partner_id = get_next_id("P")
      partner_name = "Partner #{p}"

      {:ok, partner_node} = create_hierarchy_node(%{
        id: partner_id,
        type: :partner,
        name: partner_name,
        metadata: %{
          email: "contact@partner#{p}.dk",
          address: generate_address(),
          phone: %{country_code: "+45", number: "#{20000000 + p * 1000}"}
        },
        created: timestamp,
        parent: "H#root"
      })

      # Link to root with retry
      :ok = link_with_retry(root_node, partner_node)

      # Progress
      if rem(p, 1) == 0, do: IO.puts("  Partner #{p}/5...")

      # Generate companies for this partner
      {company_total, updated_map} = generate_companies(partner_node, p, timestamp, buildings_per_property, acc_companies)

      {acc_total + 2 + company_total, updated_map}
    end)
  end

  defp generate_companies(partner_node, partner_idx, timestamp, buildings_per_property, company_map) do
    total_items = 0

    Enum.reduce(1..20, {total_items, company_map}, fn f, {acc_total, acc_map} ->
      company_id = get_next_id("C")
      company_name = "Company #{partner_idx}_#{f}"

      {:ok, company_node} = create_hierarchy_node(%{
        id: company_id,
        type: :company,
        name: company_name,
        metadata: %{
          email: "contact@firma#{partner_idx}_#{f}.dk",
          address: generate_address(),
          cvr: 10000000 + partner_idx * 1000 + f,
          phone: %{country_code: "+45", number: "#{30000000 + partner_idx * 10000 + f * 100}"},
          contact: "Manager #{f}",
          homepage: "https://company#{partner_idx}_#{f}.example.com",
          status: :active,
          sla: Enum.random([:standard, :premium, :enterprise])
        },
        created: timestamp,
        parent: "H#root#P##{partner_node.id}"
      })

      # Link to partner
      :ok = link_with_retry(partner_node, company_node)

      # Grant permission to limited user for first company of partner 1
      if partner_idx == 1 and f == 1 do
        Repo.grant_permission("stel@enity.io", "C##{company_id}", :admin)
      end

      # Generate properties for this company
      property_total = generate_properties(company_node, partner_idx, f, timestamp, buildings_per_property)

      updated_map = Map.put(acc_map, {partner_idx, f}, company_id)
      {acc_total + 2 + property_total, updated_map}
    end)
  end

  defp generate_properties(company_node, partner_idx, company_idx, timestamp, buildings_per_property) do
    total_items = 0

    Enum.reduce(1..50, total_items, fn e, acc_total ->
      property_id = get_next_id("PR")
      property_name = "Property #{partner_idx}_#{company_idx}_#{e}"
      {lat, long} = generate_coordinates()

      {:ok, property_node} = create_hierarchy_node(%{
        id: property_id,
        type: :property,
        name: property_name,
        metadata: %{
          location: %{lat: lat, long: long},
          address: generate_address(),
          usage: Enum.random(["Office", "Residential", "Industrial", "Mixed"]),
          bbr: "BBR#{property_id}",
          weather_station: "DMI_#{Enum.random(1000..9999)}"
        },
        created: timestamp,
        parent: "H#root#P##{company_node.parent |> String.split("#") |> List.last()}#C##{company_node.id}"
      })

      # Link to company
      :ok = link_with_retry(company_node, property_node)

      # Generate buildings for this property
      building_total = generate_buildings(property_node, partner_idx, company_idx, e, timestamp, buildings_per_property)

      acc_total + 2 + building_total
    end)
  end

  defp generate_buildings(property_node, partner_idx, company_idx, property_idx, timestamp, buildings_per_property) do
    total_items = 0

    Enum.reduce(1..buildings_per_property, total_items, fn b, acc_total ->
      building_id = get_next_id("B")
      building_name = "Building #{partner_idx}_#{company_idx}_#{property_idx}_#{b}"
      {lat, long} = extract_coordinates(property_node.metadata)

      {:ok, building_node} = create_hierarchy_node(%{
        id: building_id,
        type: :building,
        name: building_name,
        metadata: %{
          email: "contact#{b}@somewhere.net",
          location: %{lat: lat, long: long},
          usage: property_node.metadata[:usage] || "Office",
          total_area: Enum.random(500..5000),
          heated_area: Enum.random(400..4500),
          bbr: property_node.metadata[:bbr] || "BBR#{building_id}",
          build_year: Enum.random(1950..2023),
          p_nr: Enum.random(10000..99999),
          ext_id: "EXT#{building_id}",
          weather_station: property_node.metadata[:weather_station] || "DMI_UNKNOWN",
          timezone: "Europe/Copenhagen"
        },
        created: timestamp,
        parent: property_node.parent <> "#PR##{property_node.id}"
      })

      # Link to property
      :ok = link_with_retry(property_node, building_node)

      # TODO: Add sensors when sensor module is implemented
      # sensor_total = generate_sensors(building_node, timestamp)

      acc_total + 2
    end)
  end

  defp create_hierarchy_node(attrs) do
    HierarchyNode.new(attrs)
    |> case do
      {:ok, node} ->
        :ok = Repo.create(node)
        {:ok, node}
      error -> error
    end
  end

  defp generate_address do
    streets = ["Hovedgade", "Stationsvej", "Skolevej", "Kirkevej", "Industrivej"]

    %{
      country: "Danmark",
      street: Enum.random(streets),
      nr: Enum.random(1..150),
      zip: Enum.random(1000..9999)
    }
  end

  defp generate_coordinates do
    lat = 55.0 + :rand.uniform() |> Float.round(5)
    long = 11.0 + :rand.uniform() |> Float.round(5)
    {lat, long}
  end

  defp extract_coordinates(metadata) do
    case metadata[:location] do
      %{lat: lat, long: long} -> {lat, long}
      _ -> generate_coordinates()
    end
  end

  defp get_next_id(prefix) do
    counter_key = "counter:#{prefix}"

    retry_with_backoff(fn ->
      case Redix.command(:redix, ["INCR", counter_key]) do
        {:ok, id} -> {:ok, id}
        {:error, reason} -> {:error, reason}
      end
    end, 3)
    |> case do
      {:ok, id} -> id
      {:error, reason} ->
        IO.puts("Error incrementing counter #{counter_key}: #{inspect(reason)}")
        raise "Failed to generate ID"
    end
  end

  defp link_with_retry(parent_node, child_node, retries \\ 3) do
    retry_with_backoff(fn ->
      Repo.link_child(parent_node, child_node)
    end, retries)
  end

  defp retry_with_backoff(fun, retries_left, attempt \\ 1) when retries_left > 0 do
    case fun.() do
      :ok -> :ok
      {:ok, result} -> {:ok, result}
      {:error, _reason} when retries_left > 1 ->
        delay = :math.pow(2, attempt) * 100 |> round()
        Process.sleep(delay)
        retry_with_backoff(fun, retries_left - 1, attempt + 1)
      {:error, reason} ->
        {:error, reason}
    end
  end
end
