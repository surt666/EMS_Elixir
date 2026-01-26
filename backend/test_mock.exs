# Start the mock
{:ok, _} = EmsBackend.Test.Mocks.MockValkeyRepo.start_link([])

# Try to set a value
IO.puts("Setting key...")
result = EmsBackend.Test.Mocks.MockValkeyRepo.set("test:key", "test:value", nil)
IO.inspect(result, label: "Set result")

# Try to get it back
IO.puts("Getting key...")
get_result = EmsBackend.Test.Mocks.MockValkeyRepo.get("test:key")
IO.inspect(get_result, label: "Get result")
