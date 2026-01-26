defmodule EmsBackend.Integration.HierarchyIntegrationTest do
  use ExUnit.Case, async: false

  alias EmsBackend
  import EmsBackend.HierarchyFixtures

  @moduletag :integration

  setup do
    # Clean up test keys before each test using Redix directly
    case Redix.command(:redix, ["KEYS", "node:*"]) do
      {:ok, keys} ->
        Enum.each(keys, fn key -> Redix.command(:redix, ["DEL", key]) end)
      _ -> :ok
    end

    case Redix.command(:redix, ["KEYS", "edge:*"]) do
      {:ok, keys} ->
        Enum.each(keys, fn key -> Redix.command(:redix, ["DEL", key]) end)
      _ -> :ok
    end

    case Redix.command(:redix, ["KEYS", "descendants:*"]) do
      {:ok, keys} ->
        Enum.each(keys, fn key -> Redix.command(:redix, ["DEL", key]) end)
      _ -> :ok
    end

    :ok
  end

  describe "create_hierarchy_node/2 with real Valkey" do
    test "creates a node and stores it in Valkey" do
      attrs = %{
        id: 1,
        name: "Test Partner",
        type: :partner,
        metadata: partner_metadata()
      }

      assert {:ok, node} = EmsBackend.create_hierarchy_node(attrs)
      assert node.name == "Test Partner"
      assert node.type == :partner

      # Verify it's actually in Valkey
      assert {:ok, retrieved} = EmsBackend.get_hierarchy_node("Partner", 1)
      assert retrieved.name == "Test Partner"
    end

    test "generates ID if not provided" do
      attrs = %{name: "Auto ID Partner", type: :partner,
        metadata: partner_metadata()}

      assert {:ok, node} = EmsBackend.create_hierarchy_node(attrs)
      assert is_integer(node.id)
      assert node.id > 0
    end
  end

  describe "full hierarchy creation" do
    @tag :full_hierarchy
    test "creates Partner -> Companies -> Properties -> Buildings" do
      # Create 1 Partner (automatically linked to Root#1)
      {:ok, _partner} = EmsBackend.create_hierarchy_node(%{
        id: 1,
        name: "Global Partner",
        type: :partner,
        metadata: partner_metadata()
      })

      # Create 2 Companies under Partner
      {:ok, _company1} = EmsBackend.create_hierarchy_node(%{
        id: 101,
        name: "Company A",
        type: :company,
        metadata: company_metadata()
      }, "Partner#1")

      {:ok, _company2} = EmsBackend.create_hierarchy_node(%{
        id: 102,
        name: "Company B",
        type: :company,
        metadata: company_metadata()
      }, "Partner#1")

      # Verify Partner has 2 children
      {:ok, partner_children} = EmsBackend.get_hierarchy_children("Partner", 1)
      assert length(partner_children) == 2
      assert Enum.any?(partner_children, fn c -> c.name == "Company A" end)
      assert Enum.any?(partner_children, fn c -> c.name == "Company B" end)

      # Create 2 Properties per Company (4 total)
      {:ok, _property1a} = EmsBackend.create_hierarchy_node(%{
        id: 201,
        name: "Property A1",
        type: :property,
        metadata: property_metadata()
      }, "Company#101")

      {:ok, _property1b} = EmsBackend.create_hierarchy_node(%{
        id: 202,
        name: "Property A2",
        type: :property,
        metadata: property_metadata()
      }, "Company#101")

      {:ok, _property2a} = EmsBackend.create_hierarchy_node(%{
        id: 203,
        name: "Property B1",
        type: :property,
        metadata: property_metadata()
      }, "Company#102")

      {:ok, _property2b} = EmsBackend.create_hierarchy_node(%{
        id: 204,
        name: "Property B2",
        type: :property,
        metadata: property_metadata()
      }, "Company#102")

      # Verify Company A has 2 properties
      {:ok, company1_children} = EmsBackend.get_hierarchy_children("Company", 101)
      assert length(company1_children) == 2
      assert Enum.any?(company1_children, fn c -> c.name == "Property A1" end)
      assert Enum.any?(company1_children, fn c -> c.name == "Property A2" end)

      # Verify Company B has 2 properties
      {:ok, company2_children} = EmsBackend.get_hierarchy_children("Company", 102)
      assert length(company2_children) == 2
      assert Enum.any?(company2_children, fn c -> c.name == "Property B1" end)
      assert Enum.any?(company2_children, fn c -> c.name == "Property B2" end)

      # Create 2 Buildings per Property (8 total)
      # Property A1 buildings
      {:ok, _} = EmsBackend.create_hierarchy_node(%{
        id: 301, name: "Building A1-1", type: :building, metadata: building_metadata()
      }, "Property#201")
      {:ok, _} = EmsBackend.create_hierarchy_node(%{
        id: 302, name: "Building A1-2", type: :building, metadata: building_metadata()
      }, "Property#201")

      # Property A2 buildings
      {:ok, _} = EmsBackend.create_hierarchy_node(%{
        id: 303, name: "Building A2-1", type: :building, metadata: building_metadata()
      }, "Property#202")
      {:ok, _} = EmsBackend.create_hierarchy_node(%{
        id: 304, name: "Building A2-2", type: :building, metadata: building_metadata()
      }, "Property#202")

      # Property B1 buildings
      {:ok, _} = EmsBackend.create_hierarchy_node(%{
        id: 305, name: "Building B1-1", type: :building, metadata: building_metadata()
      }, "Property#203")
      {:ok, _} = EmsBackend.create_hierarchy_node(%{
        id: 306, name: "Building B1-2", type: :building, metadata: building_metadata()
      }, "Property#203")

      # Property B2 buildings
      {:ok, _} = EmsBackend.create_hierarchy_node(%{
        id: 307, name: "Building B2-1", type: :building, metadata: building_metadata()
      }, "Property#204")
      {:ok, _} = EmsBackend.create_hierarchy_node(%{
        id: 308, name: "Building B2-2", type: :building, metadata: building_metadata()
      }, "Property#204")

      # Verify each property has 2 buildings
      {:ok, property1a_children} = EmsBackend.get_hierarchy_children("Property", 201)
      assert length(property1a_children) == 2
      assert Enum.any?(property1a_children, fn c -> c.name == "Building A1-1" end)

      {:ok, property1b_children} = EmsBackend.get_hierarchy_children("Property", 202)
      assert length(property1b_children) == 2

      {:ok, property2a_children} = EmsBackend.get_hierarchy_children("Property", 203)
      assert length(property2a_children) == 2

      {:ok, property2b_children} = EmsBackend.get_hierarchy_children("Property", 204)
      assert length(property2b_children) == 2

      # Test ancestor traversal - building should have 4 ancestors (Property -> Company -> Partner -> Root)
      {:ok, ancestors} = EmsBackend.get_hierarchy_ancestors("Building", 301)
      assert length(ancestors) == 4
      assert Enum.at(ancestors, 0).name == "Property A1"
      assert Enum.at(ancestors, 1).name == "Company A"
      assert Enum.at(ancestors, 2).name == "Global Partner"
      assert Enum.at(ancestors, 3).name == "Root"

      # Test descendant traversal - partner should have 14 descendants
      # (2 companies + 4 properties + 8 buildings)
      {:ok, descendants} = EmsBackend.get_hierarchy_descendants("Partner", 1)
      assert length(descendants) == 14

      # Company should have 6 descendants (2 properties + 4 buildings)
      {:ok, company1_descendants} = EmsBackend.get_hierarchy_descendants("Company", 101)
      assert length(company1_descendants) == 6
    end
  end

  describe "hierarchy traversal with real Valkey" do
    setup do
      # Create a 4-level hierarchy: Partner -> Company -> Property -> Building
      {:ok, partner} = EmsBackend.create_hierarchy_node(%{
        id: 1,
        name: "Test Partner",
        type: :partner,
        metadata: partner_metadata()
      })

      {:ok, company} = EmsBackend.create_hierarchy_node(%{
        id: 1001,
        name: "Test Company",
        type: :company,
        metadata: company_metadata()
      }, "Partner#1")

      {:ok, property} = EmsBackend.create_hierarchy_node(%{
        id: 2001,
        name: "Test Property",
        type: :property,
        metadata: property_metadata()
      }, "Company#1001")

      {:ok, building} = EmsBackend.create_hierarchy_node(%{
        id: 3001,
        name: "Test Building",
        type: :building,
        metadata: building_metadata()
      }, "Property#2001")

      %{partner: partner, company: company, property: property, building: building}
    end

    test "get_hierarchy_parent returns correct parent", %{building: _building} do
      {:ok, parent} = EmsBackend.get_hierarchy_parent("Building", 3001)
      assert parent.name == "Test Property"
      assert parent.type == :property
    end

    test "get_hierarchy_children returns correct children", %{company: _company} do
      {:ok, children} = EmsBackend.get_hierarchy_children("Company", 1001)
      assert length(children) == 1
      assert hd(children).name == "Test Property"
    end

    test "get_hierarchy_ancestors returns full path to root", %{building: _building} do
      {:ok, ancestors} = EmsBackend.get_hierarchy_ancestors("Building", 3001)
      # Now includes Partner and Root as well
      assert length(ancestors) == 4
      assert Enum.at(ancestors, 0).name == "Test Property"
      assert Enum.at(ancestors, 1).name == "Test Company"
      assert Enum.at(ancestors, 2).name == "Test Partner"
      assert Enum.at(ancestors, 3).name == "Root"
    end

    test "get_hierarchy_descendants returns all descendants", %{company: _company} do
      {:ok, descendants} = EmsBackend.get_hierarchy_descendants("Company", 1001)
      assert length(descendants) == 2
      names = Enum.map(descendants, & &1.name)
      assert "Test Property" in names
      assert "Test Building" in names
    end
  end

  describe "unlink_hierarchy_nodes/5 with real Valkey" do
    test "removes parent-child relationship" do
      {:ok, _partner} = EmsBackend.create_hierarchy_node(%{
        id: 5,
        name: "Test Partner",
        type: :partner,
        metadata: partner_metadata()
      })

      {:ok, _parent} = EmsBackend.create_hierarchy_node(%{
        id: 5001,
        name: "Parent",
        type: :company,
        metadata: company_metadata()
      }, "Partner#5")

      {:ok, _child} = EmsBackend.create_hierarchy_node(%{
        id: 6001,
        name: "Child",
        type: :property,
        metadata: property_metadata()
      }, "Company#5001")

      # Verify link exists
      {:ok, children} = EmsBackend.get_hierarchy_children("Company", 5001)
      assert length(children) == 1

      # Unlink
      :ok = EmsBackend.unlink_hierarchy_nodes("Company", 5001, "Property", 6001)

      # Verify link is gone
      {:ok, children} = EmsBackend.get_hierarchy_children("Company", 5001)
      assert length(children) == 0

      {:ok, parent_result} = EmsBackend.get_hierarchy_parent("Property", 6001)
      assert parent_result == nil
    end
  end
end
