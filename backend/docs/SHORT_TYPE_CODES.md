# Short Type Code Optimization

## Summary

Implemented compact type codes in node references and keys to reduce memory usage in Valkey.

## Type Code Mapping

| Full Name | Short Code | Savings per ref |
|-----------|------------|----------------|
| Root      | R          | 3 bytes        |
| Partner   | P          | 6 bytes        |
| Company   | C          | 6 bytes        |
| Property  | PR         | 6 bytes        |
| Building  | B          | 7 bytes        |
| Area      | A          | 3 bytes        |
| Group     | G          | 4 bytes        |

## Changes Made

### 1. Node References
**Before:** `Company#1001`, `Property#2001`, `Building#3001`
**After:** `C#1001`, `PR#2001`, `B#3001`

Savings: 3-7 bytes per reference

### 2. Node Keys
**Before:** `node:Company#1001`
**After:** `node:C#1001`

Savings: 6 bytes per node

### 3. Hexastore Edge Keys
**Before:** `edge:Company#101:has_child:Property#201`
**After:** `edge:C#101:has_child:PR#201`

Savings: 12 bytes per edge key × 6 keys = 72 bytes per edge

### 4. Descendant Set Keys
**Note:** Still use full names for clarity
Format: `descendants:C#101:property` (not `descendants:C#101:pr`)

This keeps the set keys readable while saving space in refs.

## Implementation Details

### Key Functions (hierarchy_valkey_impl.ex)

```elixir
# Convert atom type to short code
defp type_to_string(:company), do: "C"
defp type_to_string(:property), do: "PR"
defp type_to_string(:building), do: "B"
# ...

# Convert short code back to atom
defp string_to_type("C"), do: :company
defp string_to_type("PR"), do: :property
defp string_to_type("B"), do: :building
# ...

# For descendant set keys (full names)
defp type_to_descendant_key(:company), do: "company"
defp type_to_descendant_key(:property), do: "property"
# Handles both atoms and strings
```

### Extraction Helper

```elixir
defp extract_type(ref) do
  [type_str, _id] = String.split(ref, "#", parts: 2)
  string_to_type(type_str)  # "C#101" → :company
end
```

## Memory Savings Calculation

For the 147K node hierarchy:

### Node Keys (147K nodes)
- Average savings: 5 bytes per key
- Total: 147,026 × 5 = **735 KB**

### Hexastore Edge Keys (882K keys)
- 147,026 edges × 6 permutations = 882,156 keys
- Savings per key: 12 bytes (6 from parent ref, 6 from child ref)
- Total: 882,156 × 12 = **10.1 MB**

### Descendant Set Members
- Each ref stored in sets: 127,500 buildings + 18,300 properties + 1,210 companies = ~147K refs
- Refs stored across multiple sets: ~500K total references
- Average savings: 5 bytes per ref
- Total: 500,000 × 5 = **2.4 MB**

### Total Savings: **~13 MB (3% reduction)**

Combined with MessagePack:
- JSON: 482 MB
- MessagePack: 410 MB
- MessagePack + Short Codes: **~397 MB**

**Total optimization: 85 MB (17.6% reduction from baseline)**

## Examples

### Node Storage
```
Before: node:Building#301 → <msgpack data>
After:  node:B#301 → <msgpack data>
```

### Hexastore Edges
```
Before: edge:Company#101:has_child:Property#201
After:  edge:C#101:has_child:PR#201
```

### Descendant Sets
```
Key:     descendants:C#101:building
Members: ["B#301", "B#302", "B#303", ...]
         ↑ Short codes in refs
```

## Testing

All 62 tests pass with short type codes.

Updated test assertions:
```elixir
# Before
assert "Company#1001" in refs

# After
assert "C#1001" in refs
```

## Backward Compatibility

⚠️ **Breaking Change:** Old data with full type names is incompatible.

Since we flushed the database, no migration needed. All new data uses short codes.

## Performance Impact

- **Faster string operations:** Shorter strings = faster comparisons
- **Better cache locality:** More keys fit in CPU cache
- **Network efficiency:** Less data transferred if using Redis replication

## Future Optimizations

Additional space-saving opportunities:

1. **Shorter edge keys:** Use `e:` instead of `edge:`
   Saves: ~2 MB (4 bytes × 882K keys)

2. **Numeric type codes:** Use integers (1-7) instead of strings
   Saves: Additional ~1 MB

3. **Compressed node IDs:** Base62 encoding for IDs
   Saves: ~1-2 bytes per ref

Combined potential: **~16 MB additional savings** (total 29 MB / 6% from baseline)
