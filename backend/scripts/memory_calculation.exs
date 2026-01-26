#!/usr/bin/env elixir

# Memory calculation for hierarchy with:
# - 15 partners
# - 1 large partner: 1000 companies, each with 12 properties, each with 8 buildings
# - 14 small partners: 15 companies each, with 30 properties each, with 5 buildings each

defmodule MemoryCalculator do
  @redis_key_overhead 96  # bytes per key in Redis
  @redis_value_overhead 50  # bytes per string value
  @redis_set_member_overhead 20  # bytes per set member

  def calculate do
    IO.puts("=== Hierarchy Memory Calculator ===\n")

    # Count nodes
    root = 1
    partners = 15

    # Large partner branch
    large_companies = 1000
    large_properties = large_companies * 12  # 12,000
    large_buildings = large_properties * 8   # 96,000

    # Small partner branches
    small_partners = 14
    small_companies = small_partners * 15    # 210
    small_properties = small_companies * 30  # 6,300
    small_buildings = small_properties * 5   # 31,500

    total_companies = large_companies + small_companies  # 1,210
    total_properties = large_properties + small_properties  # 18,300
    total_buildings = large_buildings + small_buildings  # 127,500
    total_nodes = root + partners + total_companies + total_properties + total_buildings

    IO.puts("Node counts:")
    IO.puts("  Root: #{root}")
    IO.puts("  Partners: #{partners}")
    IO.puts("  Companies: #{total_companies |> format_number()}")
    IO.puts("  Properties: #{total_properties |> format_number()}")
    IO.puts("  Buildings: #{total_buildings |> format_number()}")
    IO.puts("  Total: #{total_nodes |> format_number()}\n")

    # Calculate node data size
    node_memory = calculate_node_memory(root, partners, total_companies, total_properties, total_buildings)

    # Calculate hexastore size
    total_edges = partners + total_companies + total_properties + total_buildings
    hexastore_memory = calculate_hexastore_memory(total_edges)

    # Calculate descendant sets size
    descendant_memory = calculate_descendant_sets_memory(
      partners,
      large_companies, large_properties, large_buildings,
      small_partners, small_companies, small_properties, small_buildings,
      total_companies, total_properties, total_buildings
    )

    total_memory = node_memory + hexastore_memory + descendant_memory

    IO.puts("\n=== Total Memory ===")
    IO.puts("Node data:        #{format_mb(node_memory)}")
    IO.puts("Hexastore:        #{format_mb(hexastore_memory)}")
    IO.puts("Descendant sets:  #{format_mb(descendant_memory)}")
    IO.puts("─────────────────────────────")
    IO.puts("Total:            #{format_mb(total_memory)}")
    IO.puts("\nApproximate memory per node: #{format_bytes(div(total_memory, total_nodes))}")
  end

  defp calculate_node_memory(root, partners, companies, properties, buildings) do
    # Estimated JSON sizes (includes key name + value + Redis overhead)
    root_size = 100 + @redis_key_overhead + @redis_value_overhead  # 246 bytes
    partner_size = 300 + @redis_key_overhead + @redis_value_overhead  # 446 bytes
    company_size = 450 + @redis_key_overhead + @redis_value_overhead  # 596 bytes
    property_size = 400 + @redis_key_overhead + @redis_value_overhead  # 546 bytes
    building_size = 500 + @redis_key_overhead + @redis_value_overhead  # 646 bytes

    total = (root * root_size) +
            (partners * partner_size) +
            (companies * company_size) +
            (properties * property_size) +
            (buildings * building_size)

    IO.puts("\nNode data breakdown:")
    IO.puts("  Root:       #{format_bytes(root * root_size)}")
    IO.puts("  Partners:   #{format_bytes(partners * partner_size)}")
    IO.puts("  Companies:  #{format_mb(companies * company_size)}")
    IO.puts("  Properties: #{format_mb(properties * property_size)}")
    IO.puts("  Buildings:  #{format_mb(buildings * building_size)}")

    total
  end

  defp calculate_hexastore_memory(total_edges) do
    keys_per_edge = 6
    total_keys = total_edges * keys_per_edge

    # Each hexastore key stores edge metadata as JSON
    # Key name: "edge:Building#301:Property#201:has_child" (~45 bytes)
    # Value: JSON with parent/child info (~250 bytes)
    key_name_size = 45
    value_size = 250

    per_key_total = key_name_size + value_size + @redis_key_overhead + @redis_value_overhead
    total = total_keys * per_key_total

    IO.puts("\nHexastore breakdown:")
    IO.puts("  Total edges:     #{total_edges |> format_number()}")
    IO.puts("  Keys per edge:   #{keys_per_edge}")
    IO.puts("  Total keys:      #{total_keys |> format_number()}")
    IO.puts("  Bytes per key:   #{per_key_total}")

    total
  end

  defp calculate_descendant_sets_memory(
    partners,
    large_companies, large_properties, large_buildings,
    small_partners, small_companies, small_properties, small_buildings,
    total_companies, total_properties, total_buildings
  ) do
    ref_size = 17  # "Building#123456"
    key_size = 35  # "descendants:Company#12345:building"

    # Root sets (4 sets: partner, company, property, building)
    root_sets = [
      {partners, "partner"},
      {total_companies, "company"},
      {total_properties, "property"},
      {total_buildings, "building"}
    ]

    root_memory = Enum.reduce(root_sets, 0, fn {count, _type}, acc ->
      set_memory = key_size + @redis_key_overhead + (count * (ref_size + @redis_set_member_overhead))
      acc + set_memory
    end)

    # Large partner sets (3 sets: company, property, building)
    large_partner_memory = key_size + @redis_key_overhead + (large_companies * (ref_size + @redis_set_member_overhead)) +
                          key_size + @redis_key_overhead + (large_properties * (ref_size + @redis_set_member_overhead)) +
                          key_size + @redis_key_overhead + (large_buildings * (ref_size + @redis_set_member_overhead))

    # Small partner sets (14 partners * 3 sets each)
    small_companies_per = div(small_companies, small_partners)
    small_properties_per = div(small_properties, small_partners)
    small_buildings_per = div(small_buildings, small_partners)

    small_partner_memory = small_partners * (
      key_size + @redis_key_overhead + (small_companies_per * (ref_size + @redis_set_member_overhead)) +
      key_size + @redis_key_overhead + (small_properties_per * (ref_size + @redis_set_member_overhead)) +
      key_size + @redis_key_overhead + (small_buildings_per * (ref_size + @redis_set_member_overhead))
    )

    # Company sets (each has 2 sets: property, building)
    # Large companies: 1000 companies
    large_company_memory = large_companies * (
      key_size + @redis_key_overhead + (12 * (ref_size + @redis_set_member_overhead)) +
      key_size + @redis_key_overhead + (96 * (ref_size + @redis_set_member_overhead))
    )

    # Small companies: 210 companies
    small_company_memory = small_companies * (
      key_size + @redis_key_overhead + (30 * (ref_size + @redis_set_member_overhead)) +
      key_size + @redis_key_overhead + (150 * (ref_size + @redis_set_member_overhead))
    )

    # Property sets (each has 1 set: building)
    large_property_memory = large_properties * (key_size + @redis_key_overhead + (8 * (ref_size + @redis_set_member_overhead)))
    small_property_memory = small_properties * (key_size + @redis_key_overhead + (5 * (ref_size + @redis_set_member_overhead)))

    total = root_memory + large_partner_memory + small_partner_memory +
            large_company_memory + small_company_memory +
            large_property_memory + small_property_memory

    IO.puts("\nDescendant sets breakdown:")
    IO.puts("  Root sets:          #{format_mb(root_memory)}")
    IO.puts("  Large partner:      #{format_mb(large_partner_memory)}")
    IO.puts("  Small partners:     #{format_mb(small_partner_memory)}")
    IO.puts("  Large companies:    #{format_mb(large_company_memory)}")
    IO.puts("  Small companies:    #{format_mb(small_company_memory)}")
    IO.puts("  Large properties:   #{format_mb(large_property_memory)}")
    IO.puts("  Small properties:   #{format_mb(small_property_memory)}")

    total
  end

  defp format_number(num) when num >= 1_000_000, do: "#{Float.round(num / 1_000_000, 2)}M"
  defp format_number(num) when num >= 1_000, do: "#{Float.round(num / 1_000, 1)}K"
  defp format_number(num), do: "#{num}"

  defp format_mb(bytes), do: "#{Float.round(bytes / 1_048_576, 2)} MB"
  defp format_bytes(bytes) when bytes >= 1024, do: "#{Float.round(bytes / 1024, 2)} KB"
  defp format_bytes(bytes), do: "#{bytes} bytes"
end

MemoryCalculator.calculate()
