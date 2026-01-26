defmodule EmsBackend.Domain.HierarchyNodeTest do
  use ExUnit.Case, async: true

  alias EmsBackend.Domain.HierarchyNode

  # Metadata helpers
  defp company_metadata do
    %{
      email: "contact@company.com",
      address: %{zip: 1000, street: "Main St", country: "Denmark", nr: 123},
      cvr: 12345678,
      phone: %{country_code: "+45", number: "12345678"},
      contact: "John Doe",
      homepage: "https://company.com",
      status: :active,
      sla: :standard
    }
  end

  defp building_metadata do
    %{
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
    }
  end

  defp partner_metadata do
    %{
      email: "partner@example.com",
      address: %{zip: 2000, street: "Partner St", country: "Denmark", nr: 1},
      phone: %{country_code: "+45", number: "87654321"}
    }
  end

  defp property_metadata do
    %{
      location: %{lat: 55.6761, long: 12.5683},
      address: %{zip: 3000, street: "Property Ave", country: "Denmark", nr: 50},
      usage: "Commercial",
      bbr: "54321",
      weather_station: "DMI_COPENHAGEN"
    }
  end

  defp area_metadata do
    %{name: "Ground Floor"}
  end

  defp group_metadata do
    %{name: "Building Group A"}
  end

  describe "new/1" do
    test "creates a valid hierarchy node" do
      attrs = %{
        name: "Acme Corp",
        type: :company,
        metadata: company_metadata()
      }

      assert {:ok, node} = HierarchyNode.new(attrs)
      assert node.name == "Acme Corp"
      assert node.type == :company
      assert node.blocked == false
      assert is_integer(node.id)
      assert %DateTime{} = node.created
    end

    test "validates name is required" do
      attrs = %{
        name: nil,
        type: :company,
        metadata: company_metadata()
      }

      assert {:error, "Name is required"} = HierarchyNode.new(attrs)
    end

    test "validates name is non-empty" do
      attrs = %{
        name: "",
        type: :company,
        metadata: company_metadata()
      }

      assert {:error, "Name must be a non-empty string"} = HierarchyNode.new(attrs)
    end

    test "validates type is required" do
      attrs = %{
        name: "Test",
        type: nil,
        metadata: company_metadata()
      }

      assert {:error, "Type is required"} = HierarchyNode.new(attrs)
    end

    test "validates type is valid" do
      attrs = %{
        name: "Test",
        type: :invalid_type,
        metadata: company_metadata()
      }

      assert {:error, msg} = HierarchyNode.new(attrs)
      assert msg =~ "Invalid node type"
    end

    test "validates metadata is required" do
      attrs = %{
        name: "Test Company",
        type: :company
      }

      assert {:error, "Metadata is required"} = HierarchyNode.new(attrs)
    end

    test "validates company metadata fields" do
      attrs = %{
        name: "Test Company",
        type: :company,
        metadata: %{email: "test@example.com"}  # Missing required fields
      }

      assert {:error, msg} = HierarchyNode.new(attrs)
      assert msg =~ "company metadata missing required fields"
    end

    test "accepts all valid node types with proper metadata" do
      test_data = [
        {:partner, partner_metadata()},
        {:company, company_metadata()},
        {:property, property_metadata()},
        {:building, building_metadata()},
        {:area, area_metadata()},
        {:group, group_metadata()}
      ]

      for {type, metadata} <- test_data do
        attrs = %{name: "Test #{type}", type: type, metadata: metadata}
        assert {:ok, _node} = HierarchyNode.new(attrs)
      end
    end
  end

  describe "block/1 and unblock/1" do
    test "blocks a node" do
      {:ok, node} = HierarchyNode.new(%{name: "Test", type: :company, metadata: company_metadata()})

      assert {:ok, blocked_node} = HierarchyNode.block(node)
      assert blocked_node.blocked == true
    end

    test "unblocks a node" do
      {:ok, node} = HierarchyNode.new(%{name: "Test", type: :company, metadata: company_metadata()})
      {:ok, blocked_node} = HierarchyNode.block(node)

      assert {:ok, unblocked_node} = HierarchyNode.unblock(blocked_node)
      assert unblocked_node.blocked == false
    end
  end

  describe "accessible?/1" do
    test "returns true for non-blocked nodes" do
      {:ok, node} = HierarchyNode.new(%{name: "Test", type: :company, metadata: company_metadata()})

      assert HierarchyNode.accessible?(node) == true
    end

    test "returns false for blocked nodes" do
      {:ok, node} = HierarchyNode.new(%{name: "Test", type: :company, metadata: company_metadata()})
      {:ok, blocked_node} = HierarchyNode.block(node)

      assert HierarchyNode.accessible?(blocked_node) == false
    end
  end

  describe "set_parent/2" do
    test "sets parent reference" do
      {:ok, node} = HierarchyNode.new(%{name: "Building 1", type: :building, metadata: building_metadata()})

      assert {:ok, updated} = HierarchyNode.set_parent(node, "C#1001")
      assert updated.parent == "C#1001"
    end

    test "can clear parent reference" do
      {:ok, node} = HierarchyNode.new(%{name: "Building 1", type: :building, parent: "C#1001", metadata: building_metadata()})

      assert {:ok, updated} = HierarchyNode.set_parent(node, nil)
      assert updated.parent == nil
    end
  end

  describe "update_metadata/2" do
    test "updates node metadata" do
      {:ok, node} = HierarchyNode.new(%{name: "Test Building", type: :building, metadata: building_metadata()})

      new_metadata = %{
        email: "updated@example.com",
        location: %{lat: 56.0, long: 13.0},
        usage: "Residential",
        total_area: 1500,
        heated_area: 1200,
        bbr: "99999",
        build_year: 2021,
        p_nr: 2,
        ext_id: "EXT456",
        weather_station: "DMI_AARHUS",
        timezone: "Europe/Copenhagen"
      }

      assert {:ok, updated} = HierarchyNode.update_metadata(node, new_metadata)
      assert updated.metadata == new_metadata
    end
  end
end
