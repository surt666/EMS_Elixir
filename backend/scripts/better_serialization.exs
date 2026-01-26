#!/usr/bin/env elixir

# Better serialization options for Valkey

Mix.install([
  {:jason, "~> 1.4"},
  {:msgpax, "~> 2.4"}
])

defmodule BetterSerialization do
  def run do
    building_node = %{
      "id" => 3001,
      "created" => "2026-01-25T12:00:00Z",
      "type" => "building",
      "name" => "Office Building A",
      "metadata" => %{
        "email" => "building@example.com",
        "location" => %{"lat" => 55.6761, "long" => 12.5683},
        "usage" => "Office",
        "total_area" => 1000,
        "heated_area" => 800,
        "bbr" => "12345",
        "build_year" => 2020,
        "p_nr" => 1,
        "ext_id" => "EXT123",
        "weather_station" => "DMI_COPENHAGEN",
        "timezone" => "Europe/Copenhagen"
      },
      "blocked" => false,
      "parent" => "Property#2001"
    }

    edge_data = %{
      "parent_id" => "Company#101",
      "child_id" => "Property#201",
      "parent_type" => "company",
      "child_type" => "property",
      "parent_name" => "Acme Corp",
      "child_name" => "Property A",
      "created" => "2026-01-25T12:00:00Z"
    }

    IO.puts("=== Optimized Serialization Comparison ===\n")

    # 1. JSON (current)
    json_building = Jason.encode!(building_node)
    json_edge = Jason.encode!(edge_data)

    # 2. JSON with short keys (b=blocked, m=metadata, etc)
    short_building = %{
      "i" => 3001,
      "c" => "2026-01-25T12:00:00Z",
      "t" => "building",
      "n" => "Office Building A",
      "m" => building_node["metadata"],
      "b" => false,
      "p" => "Property#2001"
    }
    json_short = Jason.encode!(short_building)

    # 3. MessagePack
    msgpack_building = Msgpax.pack!(building_node) |> IO.iodata_to_binary()
    msgpack_edge = Msgpax.pack!(edge_data) |> IO.iodata_to_binary()

    # 4. Compressed JSON (gzip)
    json_compressed = :zlib.gzip(json_building)
    json_edge_compressed = :zlib.gzip(json_edge)

    # 5. MessagePack + gzip
    msgpack_compressed = :zlib.gzip(msgpack_building)

    IO.puts("Building node (#{byte_size(json_building)} chars in JSON):")
    IO.puts("  1. JSON (current):           #{byte_size(json_building)} bytes")
    IO.puts("  2. JSON (short keys):        #{byte_size(json_short)} bytes  (#{savings(json_building, json_short)}% smaller)")
    IO.puts("  3. MessagePack:              #{byte_size(msgpack_building)} bytes  (#{savings(json_building, msgpack_building)}% smaller)")
    IO.puts("  4. JSON + gzip:              #{byte_size(json_compressed)} bytes  (#{savings(json_building, json_compressed)}% smaller)")
    IO.puts("  5. MessagePack + gzip:       #{byte_size(msgpack_compressed)} bytes  (#{savings(json_building, msgpack_compressed)}% smaller)")
    IO.puts("")

    IO.puts("Edge data (#{byte_size(json_edge)} chars in JSON):")
    IO.puts("  1. JSON (current):           #{byte_size(json_edge)} bytes")
    IO.puts("  2. MessagePack:              #{byte_size(msgpack_edge)} bytes  (#{savings(json_edge, msgpack_edge)}% smaller)")
    IO.puts("  3. JSON + gzip:              #{byte_size(json_edge_compressed)} bytes  (#{savings(json_edge, json_edge_compressed)}% smaller)")
    IO.puts("")

    # Projection for full hierarchy
    IO.puts("=== Full Hierarchy Projection (147K nodes) ===\n")

    # total_nodes = 147_026
    # building_ratio = 0.867  # 127,500 buildings
    # edge_count = total_nodes

    # Current JSON baseline (from previous calculation)
    json_total = 460_000_000  # ~460 MB

    # MessagePack projection
    msgpack_node_savings_pct = savings_numeric(json_building, msgpack_building)
    msgpack_edge_savings_pct = savings_numeric(json_edge, msgpack_edge)
    msgpack_total = json_total * (1 - (msgpack_node_savings_pct * 0.6 + msgpack_edge_savings_pct * 0.4))

    # Gzip JSON projection (conservative estimate: 60% compression)
    gzip_savings = 0.6
    gzip_total = json_total * (1 - gzip_savings)

    IO.puts("Total memory (nodes + edges + descendant sets):")
    IO.puts("  JSON (current):        #{format_mb(json_total)}")
    IO.puts("  MessagePack:           #{format_mb(msgpack_total)}  (saves ~#{format_mb(json_total - msgpack_total)})")
    IO.puts("  JSON + gzip:           #{format_mb(gzip_total)}  (saves ~#{format_mb(json_total - gzip_total)})")
    IO.puts("")

    IO.puts("=== Recommendations ===\n")
    IO.puts("1. MessagePack (BEST CHOICE):")
    IO.puts("   ✓ 20-30% smaller than JSON")
    IO.puts("   ✓ Faster to encode/decode than JSON")
    IO.puts("   ✓ Widely supported (can view with msgpack-cli)")
    IO.puts("   ✓ Simple drop-in replacement")
    IO.puts("   ✗ Requires msgpax dependency")
    IO.puts("")

    IO.puts("2. JSON + Compression (gzip/LZ4):")
    IO.puts("   ✓ 50-60% smaller")
    IO.puts("   ✓ Use existing JSON tooling")
    IO.puts("   ✗ CPU overhead for compress/decompress")
    IO.puts("   ✗ Can't query compressed data in Redis")
    IO.puts("")

    IO.puts("3. JSON with shorter keys:")
    IO.puts("   ✓ 10-15% smaller")
    IO.puts("   ✓ No dependencies")
    IO.puts("   ✗ Less readable")
    IO.puts("   ✗ Mapping layer needed")
    IO.puts("")

    IO.puts("For 482 MB → MessagePack would reduce to ~350-380 MB")
  end

  defp savings(original, new) do
    saved = byte_size(original) - byte_size(new)
    pct = Float.round(saved / byte_size(original) * 100, 1)
    if pct > 0, do: "+#{pct}", else: "#{pct}"
  end

  defp savings_numeric(original, new) do
    saved = byte_size(original) - byte_size(new)
    saved / byte_size(original)
  end

  defp format_mb(bytes) do
    "#{Float.round(bytes / 1_048_576, 1)} MB"
  end
end

BetterSerialization.run()
