#!/usr/bin/env elixir

# Demonstrates what's actually stored in Valkey

IO.puts("=== What's Actually Stored in Valkey ===\n")

IO.puts("1. NODE DATA (stored as JSON strings):")
IO.puts("   Key: node:Company#101")
IO.puts("   Value: ")
IO.puts(~s(   {
     "id": 101,
     "created": "2025-01-25T12:00:00Z",
     "type": "company",
     "name": "Acme Corp",
     "metadata": {
       "email": "contact@company.com",
       "address": {"zip": 1000, "street": "Main St", "country": "Denmark", "nr": 123},
       "cvr": 12345678,
       "phone": {"country_code": "+45", "number": "12345678"},
       "contact": "John Doe",
       "homepage": "https://company.com",
       "status": "active",
       "sla": "standard"
     },
     "blocked": false,
     "parent": "Partner#1"
   }))
IO.puts("   Storage: Redis String (~450 bytes)")
IO.puts("")

IO.puts("2. HEXASTORE EDGES (6 keys per edge, each storing JSON):")
IO.puts("   Edge: Company#101 → Property#201")
IO.puts("   Generates 6 keys, each with same JSON value:")
IO.puts("")
IO.puts("   Key: edge:Company#101:has_child:Property#201  (SPO)")
IO.puts("   Key: edge:Company#101:Property#201:has_child  (SOP)")
IO.puts("   Key: edge:has_child:Company#101:Property#201  (PSO)")
IO.puts("   Key: edge:has_child:Property#201:Company#101  (POS)")
IO.puts("   Key: edge:Property#201:Company#101:has_child  (OSP)")
IO.puts("   Key: edge:Property#201:has_child:Company#101  (OPS)")
IO.puts("")
IO.puts("   All 6 values: ")
IO.puts(~s(   {
     "parent_id": "Company#101",
     "child_id": "Property#201",
     "parent_type": "company",
     "child_type": "property",
     "parent_name": "Acme Corp",
     "child_name": "Property A",
     "created": "2025-01-25T12:05:00Z"
   }))
IO.puts("   Storage: 6 × Redis String (~250 bytes each)")
IO.puts("")

IO.puts("3. DESCENDANT SETS (Redis Sets, NOT JSON):")
IO.puts("   Key: descendants:Company#101:building")
IO.puts("   Type: Redis Set")
IO.puts("   Members: [")
IO.puts("     \"Building#301\",")
IO.puts("     \"Building#302\",")
IO.puts("     \"Building#303\",")
IO.puts("     ...")
IO.puts("   ]")
IO.puts("   Storage: Redis Set with string members (~17 bytes per ref)")
IO.puts("")

IO.puts("=== Summary ===")
IO.puts("Everything is in Valkey:")
IO.puts("  • Nodes → JSON strings (via Jason.encode!)")
IO.puts("  • Edges → JSON strings (via Jason.encode!)")
IO.puts("  • Descendant sets → Redis SETs with string refs")
IO.puts("")
IO.puts("The ~482 MB calculation is for data AT REST in Valkey memory.")
