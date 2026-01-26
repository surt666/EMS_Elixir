#!/usr/bin/env elixir

# Compare serialization formats for Valkey storage

defmodule SerializationComparison do
  def run do
    # Sample node data
    company_node = %{
      id: 101,
      created: DateTime.utc_now(),
      type: :company,
      name: "Acme Corporation",
      metadata: %{
        email: "contact@company.com",
        address: %{zip: 1000, street: "Main Street", country: "Denmark", nr: 123},
        cvr: 12345678,
        phone: %{country_code: "+45", number: "12345678"},
        contact: "John Doe",
        homepage: "https://company.com",
        status: :active,
        sla: :standard
      },
      blocked: false,
      parent: "Partner#1"
    }

    building_node = %{
      id: 3001,
      created: DateTime.utc_now(),
      type: :building,
      name: "Office Building A",
      metadata: %{
        email: "building@example.com",
        location: %{lat: 55.6761, long: 12.5683},
        usage: "Office",
        total_area: 1000,
        heated_area: 800,
        bbr: "12345",
        build_year: 2020,
        p_nr: 1,
        ext_id: "EXT123",
        weather_station: "DMI_COPENHAGEN",
        timezone: "Europe/Copenhagen"
      },
      blocked: false,
      parent: "Property#2001"
    }

    edge_data = %{
      parent_id: "Company#101",
      child_id: "Property#201",
      parent_type: :company,
      child_type: :property,
      parent_name: "Acme Corp",
      child_name: "Property A",
      created: DateTime.utc_now()
    }

    IO.puts("=== Serialization Format Comparison ===\n")

    # JSON (current implementation)
    json_company = Jason.encode!(company_node)
    json_building = Jason.encode!(building_node)
    json_edge = Jason.encode!(edge_data)

    IO.puts("1. JSON (current):")
    IO.puts("   Company node:  #{byte_size(json_company)} bytes")
    IO.puts("   Building node: #{byte_size(json_building)} bytes")
    IO.puts("   Edge data:     #{byte_size(json_edge)} bytes")
    IO.puts("")

    # Erlang Term Format
    etf_company = :erlang.term_to_binary(company_node)
    etf_building = :erlang.term_to_binary(building_node)
    etf_edge = :erlang.term_to_binary(edge_data)

    IO.puts("2. Erlang Term Format (ETF):")
    IO.puts("   Company node:  #{byte_size(etf_company)} bytes")
    IO.puts("   Building node: #{byte_size(etf_building)} bytes")
    IO.puts("   Edge data:     #{byte_size(etf_edge)} bytes")
    IO.puts("")

    # Compressed ETF
    etf_compressed_company = :erlang.term_to_binary(company_node, [:compressed])
    etf_compressed_building = :erlang.term_to_binary(building_node, [:compressed])
    etf_compressed_edge = :erlang.term_to_binary(edge_data, [:compressed])

    IO.puts("3. Compressed ETF:")
    IO.puts("   Company node:  #{byte_size(etf_compressed_company)} bytes")
    IO.puts("   Building node: #{byte_size(etf_compressed_building)} bytes")
    IO.puts("   Edge data:     #{byte_size(etf_compressed_edge)} bytes")
    IO.puts("")

    # Calculate savings
    IO.puts("=== Savings vs JSON ===\n")

    company_savings = calculate_savings(byte_size(json_company), byte_size(etf_company))
    building_savings = calculate_savings(byte_size(json_building), byte_size(etf_building))
    edge_savings = calculate_savings(byte_size(json_edge), byte_size(etf_edge))

    company_compressed_savings = calculate_savings(byte_size(json_company), byte_size(etf_compressed_company))
    building_compressed_savings = calculate_savings(byte_size(json_building), byte_size(etf_compressed_building))
    edge_compressed_savings = calculate_savings(byte_size(json_edge), byte_size(etf_compressed_edge))

    IO.puts("ETF (uncompressed):")
    IO.puts("   Company:  #{company_savings}% smaller")
    IO.puts("   Building: #{building_savings}% smaller")
    IO.puts("   Edge:     #{edge_savings}% smaller")
    IO.puts("")

    IO.puts("ETF (compressed):")
    IO.puts("   Company:  #{company_compressed_savings}% smaller")
    IO.puts("   Building: #{building_compressed_savings}% smaller")
    IO.puts("   Edge:     #{edge_compressed_savings}% smaller")
    IO.puts("")

    # Memory projection for full hierarchy
    IO.puts("=== Full Hierarchy Projection (147K nodes) ===\n")

    # Assume 82% buildings, 12% properties, 1% companies, 5% other
    total_nodes = 147_026
    building_count = round(total_nodes * 0.82)
    property_count = round(total_nodes * 0.12)
    company_count = round(total_nodes * 0.01)
    other_count = total_nodes - building_count - property_count - company_count
    edge_count = total_nodes

    json_total = (building_count * byte_size(json_building)) +
                 (property_count * 400) +  # Estimated property size
                 (company_count * byte_size(json_company)) +
                 (other_count * 300) +  # Estimated partner/root size
                 (edge_count * byte_size(json_edge) * 6)  # 6 hexastore keys per edge

    etf_total = (building_count * byte_size(etf_building)) +
                (property_count * 280) +  # Estimated ETF property size
                (company_count * byte_size(etf_company)) +
                (other_count * 210) +  # Estimated ETF partner/root size
                (edge_count * byte_size(etf_edge) * 6)

    etf_compressed_total = (building_count * byte_size(etf_compressed_building)) +
                           (property_count * 240) +
                           (company_count * byte_size(etf_compressed_company)) +
                           (other_count * 180) +
                           (edge_count * byte_size(etf_compressed_edge) * 6)

    IO.puts("Node + Edge data only (excludes descendant sets):")
    IO.puts("   JSON:              #{format_mb(json_total)}")
    IO.puts("   ETF:               #{format_mb(etf_total)}")
    IO.puts("   ETF (compressed):  #{format_mb(etf_compressed_total)}")
    IO.puts("")

    total_savings = calculate_savings(json_total, etf_total)
    compressed_savings = calculate_savings(json_total, etf_compressed_total)

    IO.puts("Potential savings:")
    IO.puts("   ETF:               ~#{format_mb(json_total - etf_total)} saved (#{total_savings}%)")
    IO.puts("   ETF (compressed):  ~#{format_mb(json_total - etf_compressed_total)} saved (#{compressed_savings}%)")
    IO.puts("")

    # With descendant sets
    descendant_sets_size = 23_700_000  # 23 MB from previous calculation

    json_with_sets = json_total + descendant_sets_size
    etf_with_sets = etf_total + descendant_sets_size
    etf_compressed_with_sets = etf_compressed_total + descendant_sets_size

    IO.puts("Including descendant sets (~23 MB):")
    IO.puts("   JSON total:              #{format_mb(json_with_sets)}")
    IO.puts("   ETF total:               #{format_mb(etf_with_sets)}")
    IO.puts("   ETF compressed total:    #{format_mb(etf_compressed_with_sets)}")
    IO.puts("")

    total_with_sets_savings = calculate_savings(json_with_sets, etf_with_sets)
    compressed_with_sets_savings = calculate_savings(json_with_sets, etf_compressed_with_sets)

    IO.puts("Overall memory savings:")
    IO.puts("   ETF:               ~#{format_mb(json_with_sets - etf_with_sets)} saved (#{total_with_sets_savings}%)")
    IO.puts("   ETF (compressed):  ~#{format_mb(json_with_sets - etf_compressed_with_sets)} saved (#{compressed_with_sets_savings}%)")

    IO.puts("\n=== Benefits of ETF ===")
    IO.puts("✓ Built into Erlang/Elixir (no dependencies)")
    IO.puts("✓ 30-50% smaller than JSON")
    IO.puts("✓ 5-10x faster encoding/decoding")
    IO.puts("✓ Preserves Elixir types (atoms, tuples)")
    IO.puts("✓ Battle-tested in production systems")
    IO.puts("✗ Not human-readable (use redis-cli --raw + hexdump)")
  end

  defp calculate_savings(original, new) do
    Float.round((original - new) / original * 100, 1)
  end

  defp format_mb(bytes) do
    "#{Float.round(bytes / 1_048_576, 2)} MB"
  end
end

SerializationComparison.run()
