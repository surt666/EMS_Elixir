defmodule EmsBackend.Repositories.HierarchyRepositoryTest do
  use ExUnit.Case, async: false

  alias EmsBackend.Domain.HierarchyNode
  alias EmsBackend.Repositories.HierarchyValkeyImpl
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

  describe "create/2 and get/3" do
    test "stores and retrieves a hierarchy node" do
      {:ok, node} = HierarchyNode.new(%{
        id: 1001,
        name: "Acme Corp",
        type: :company,
        metadata: company_metadata()
      })

      assert :ok = HierarchyValkeyImpl.create(node)
      assert {:ok, retrieved} = HierarchyValkeyImpl.get("Company", 1001)

      assert retrieved.id == 1001
      assert retrieved.name == "Acme Corp"
      assert retrieved.type == :company
    end

    test "returns error for non-existent node" do
      assert {:error, :not_found} = HierarchyValkeyImpl.get("Company", 999)
    end
  end

  describe "link_child/3 with hexastore indexing" do
    test "creates parent-child relationship with all 6 hexastore indices" do
      {:ok, company} = HierarchyNode.new(%{id: 1001, name: "Acme Corp", type: :company, metadata: company_metadata()})
      {:ok, property} = HierarchyNode.new(%{id: 2001, name: "Building A", type: :property, metadata: property_metadata()})

      HierarchyValkeyImpl.create(company)
      HierarchyValkeyImpl.create(property)

      assert :ok = HierarchyValkeyImpl.link_child(company, property)

      # Verify all 6 hexastore permutations exist
      assert {:ok, _} = Redix.command(:redix, ["GET", "edge:Company#1001:has_child:Property#2001"])  # SPO
      assert {:ok, _} = Redix.command(:redix, ["GET", "edge:Company#1001:Property#2001:has_child"])  # SOP
      assert {:ok, _} = Redix.command(:redix, ["GET", "edge:has_child:Company#1001:Property#2001"])  # PSO
      assert {:ok, _} = Redix.command(:redix, ["GET", "edge:has_child:Property#2001:Company#1001"])  # POS
      assert {:ok, _} = Redix.command(:redix, ["GET", "edge:Property#2001:Company#1001:has_child"])  # OSP
      assert {:ok, _} = Redix.command(:redix, ["GET", "edge:Property#2001:has_child:Company#1001"])  # OPS
    end

    test "stores edge metadata in all indices" do
      {:ok, company} = HierarchyNode.new(%{id: 1001, name: "Acme Corp", type: :company, metadata: company_metadata()})
      {:ok, property} = HierarchyNode.new(%{id: 2001, name: "Building A", type: :property, metadata: property_metadata()})

      HierarchyValkeyImpl.create(company)
      HierarchyValkeyImpl.create(property)
      HierarchyValkeyImpl.link_child(company, property)

      {:ok, edge_msgpack} = Redix.command(:redix, ["GET", "edge:C#1001:has_child:PR#2001"])
      {:ok, edge_data} = Msgpax.unpack(edge_msgpack)

      assert edge_data["parent_id"] == "C#1001"
      assert edge_data["child_id"] == "PR#2001"
      assert edge_data["parent_name"] == "Acme Corp"
      assert edge_data["child_name"] == "Building A"
    end
  end

  describe "get_children/3" do
    test "retrieves all children of a node" do
      {:ok, company} = HierarchyNode.new(%{id: 1001, name: "Acme Corp", type: :company, metadata: company_metadata()})
      {:ok, property1} = HierarchyNode.new(%{id: 2001, name: "Property A", type: :property, metadata: property_metadata()})
      {:ok, property2} = HierarchyNode.new(%{id: 2002, name: "Property B", type: :property, metadata: property_metadata()})

      HierarchyValkeyImpl.create(company)
      HierarchyValkeyImpl.create(property1)
      HierarchyValkeyImpl.create(property2)

      HierarchyValkeyImpl.link_child(company, property1)
      HierarchyValkeyImpl.link_child(company, property2)

      {:ok, children} = HierarchyValkeyImpl.get_children("Company", 1001)

      assert length(children) == 2
      assert Enum.any?(children, fn c -> c.name == "Property A" end)
      assert Enum.any?(children, fn c -> c.name == "Property B" end)
    end

    test "returns empty list when node has no children" do
      {:ok, company} = HierarchyNode.new(%{id: 1001, name: "Acme Corp", type: :company, metadata: company_metadata()})
      HierarchyValkeyImpl.create(company)

      {:ok, children} = HierarchyValkeyImpl.get_children("Company", 1001)

      assert children == []
    end
  end

  describe "get_parent/3" do
    test "retrieves parent of a node" do
      {:ok, company} = HierarchyNode.new(%{id: 1001, name: "Acme Corp", type: :company, metadata: company_metadata()})
      {:ok, property} = HierarchyNode.new(%{id: 2001, name: "Property A", type: :property, metadata: property_metadata()})

      HierarchyValkeyImpl.create(company)
      HierarchyValkeyImpl.create(property)
      HierarchyValkeyImpl.link_child(company, property)

      {:ok, parent} = HierarchyValkeyImpl.get_parent("Property", 2001)

      assert parent.id == 1001
      assert parent.name == "Acme Corp"
      assert parent.type == :company
    end

    test "returns nil when node has no parent" do
      {:ok, company} = HierarchyNode.new(%{id: 1001, name: "Acme Corp", type: :company, metadata: company_metadata()})
      HierarchyValkeyImpl.create(company)

      {:ok, parent} = HierarchyValkeyImpl.get_parent("Company", 1001)

      assert parent == nil
    end
  end

  describe "unlink_child/5" do
    test "removes parent-child relationship and all 6 hexastore indices" do
      {:ok, company} = HierarchyNode.new(%{id: 1001, name: "Acme Corp", type: :company, metadata: company_metadata()})
      {:ok, property} = HierarchyNode.new(%{id: 2001, name: "Property A", type: :property, metadata: property_metadata()})

      HierarchyValkeyImpl.create(company)
      HierarchyValkeyImpl.create(property)
      HierarchyValkeyImpl.link_child(company, property)

      assert :ok = HierarchyValkeyImpl.unlink_child("Company", 1001, "Property", 2001)

      # Verify all 6 hexastore keys are deleted
      assert {:ok, nil} = Redix.command(:redix, ["GET", "edge:Company#1001:has_child:Property#2001"])  # SPO
      assert {:ok, nil} = Redix.command(:redix, ["GET", "edge:Company#1001:Property#2001:has_child"])  # SOP
      assert {:ok, nil} = Redix.command(:redix, ["GET", "edge:has_child:Company#1001:Property#2001"])  # PSO
      assert {:ok, nil} = Redix.command(:redix, ["GET", "edge:has_child:Property#2001:Company#1001"])  # POS
      assert {:ok, nil} = Redix.command(:redix, ["GET", "edge:Property#2001:Company#1001:has_child"])  # OSP
      assert {:ok, nil} = Redix.command(:redix, ["GET", "edge:Property#2001:has_child:Company#1001"])  # OPS

      {:ok, children} = HierarchyValkeyImpl.get_children("Company", 1001)
      assert children == []
    end
  end

  describe "get_ancestors/3" do
    test "retrieves full path to root" do
      # Create hierarchy: Company -> Property -> Building
      {:ok, company} = HierarchyNode.new(%{id: 1001, name: "Acme Corp", type: :company, metadata: company_metadata()})
      {:ok, property} = HierarchyNode.new(%{id: 2001, name: "Property A", type: :property, metadata: property_metadata()})
      {:ok, building} = HierarchyNode.new(%{id: 3001, name: "Building 1", type: :building, metadata: building_metadata()})

      HierarchyValkeyImpl.create(company)
      HierarchyValkeyImpl.create(property)
      HierarchyValkeyImpl.create(building)

      HierarchyValkeyImpl.link_child(company, property)
      HierarchyValkeyImpl.link_child(property, building)

      {:ok, ancestors} = HierarchyValkeyImpl.get_ancestors("Building", 3001)

      assert length(ancestors) == 2
      assert Enum.at(ancestors, 0).name == "Property A"
      assert Enum.at(ancestors, 1).name == "Acme Corp"
    end

    test "returns empty list for root node" do
      {:ok, company} = HierarchyNode.new(%{id: 1001, name: "Acme Corp", type: :company, metadata: company_metadata()})
      HierarchyValkeyImpl.create(company)

      {:ok, ancestors} = HierarchyValkeyImpl.get_ancestors("Company", 1001)

      assert ancestors == []
    end
  end

  describe "get_descendants/3" do
    test "retrieves all descendants recursively" do
      # Create hierarchy: Company -> Property -> Building
      {:ok, company} = HierarchyNode.new(%{id: 1001, name: "Acme Corp", type: :company, metadata: company_metadata()})
      {:ok, property} = HierarchyNode.new(%{id: 2001, name: "Property A", type: :property, metadata: property_metadata()})
      {:ok, building1} = HierarchyNode.new(%{id: 3001, name: "Building 1", type: :building, metadata: building_metadata()})
      {:ok, building2} = HierarchyNode.new(%{id: 3002, name: "Building 2", type: :building, metadata: building_metadata()})

      HierarchyValkeyImpl.create(company)
      HierarchyValkeyImpl.create(property)
      HierarchyValkeyImpl.create(building1)
      HierarchyValkeyImpl.create(building2)

      HierarchyValkeyImpl.link_child(company, property)
      HierarchyValkeyImpl.link_child(property, building1)
      HierarchyValkeyImpl.link_child(property, building2)

      {:ok, descendants} = HierarchyValkeyImpl.get_descendants("Company", 1001)

      assert length(descendants) == 3
      assert Enum.any?(descendants, fn d -> d.name == "Property A" end)
      assert Enum.any?(descendants, fn d -> d.name == "Building 1" end)
      assert Enum.any?(descendants, fn d -> d.name == "Building 2" end)
    end
  end

  describe "descendant sets for O(1) queries" do
    test "creates descendant sets when linking nodes" do
      {:ok, company} = HierarchyNode.new(%{id: 1001, name: "Acme Corp", type: :company, metadata: company_metadata()})
      {:ok, property} = HierarchyNode.new(%{id: 2001, name: "Property A", type: :property, metadata: property_metadata()})

      HierarchyValkeyImpl.create(company)
      HierarchyValkeyImpl.create(property)
      HierarchyValkeyImpl.link_child(company, property)

      # Verify descendant set exists
      {:ok, members} = Redix.command(:redix, ["SMEMBERS", "descendants:C#1001:property"])
      assert "PR#2001" in members
    end

    test "maintains transitive closure in descendant sets" do
      # Create hierarchy: Company -> Property -> Building
      {:ok, company} = HierarchyNode.new(%{id: 1001, name: "Acme Corp", type: :company, metadata: company_metadata()})
      {:ok, property} = HierarchyNode.new(%{id: 2001, name: "Property A", type: :property, metadata: property_metadata()})
      {:ok, building} = HierarchyNode.new(%{id: 3001, name: "Building 1", type: :building, metadata: building_metadata()})

      HierarchyValkeyImpl.create(company)
      HierarchyValkeyImpl.create(property)
      HierarchyValkeyImpl.create(building)

      HierarchyValkeyImpl.link_child(company, property)
      HierarchyValkeyImpl.link_child(property, building)

      # Company should have property in its property set
      {:ok, property_members} = Redix.command(:redix, ["SMEMBERS", "descendants:C#1001:property"])
      assert "PR#2001" in property_members

      # Company should have building in its building set (transitive)
      {:ok, building_members} = Redix.command(:redix, ["SMEMBERS", "descendants:C#1001:building"])
      assert "B#3001" in building_members

      # Property should also have building in its set
      {:ok, property_building_members} = Redix.command(:redix, ["SMEMBERS", "descendants:PR#2001:building"])
      assert "B#3001" in property_building_members
    end

    test "get_descendants_by_type returns descendants using sets" do
      {:ok, company} = HierarchyNode.new(%{id: 1001, name: "Acme Corp", type: :company, metadata: company_metadata()})
      {:ok, property1} = HierarchyNode.new(%{id: 2001, name: "Property A", type: :property, metadata: property_metadata()})
      {:ok, property2} = HierarchyNode.new(%{id: 2002, name: "Property B", type: :property, metadata: property_metadata()})
      {:ok, building1} = HierarchyNode.new(%{id: 3001, name: "Building 1", type: :building, metadata: building_metadata()})
      {:ok, building2} = HierarchyNode.new(%{id: 3002, name: "Building 2", type: :building, metadata: building_metadata()})

      HierarchyValkeyImpl.create(company)
      HierarchyValkeyImpl.create(property1)
      HierarchyValkeyImpl.create(property2)
      HierarchyValkeyImpl.create(building1)
      HierarchyValkeyImpl.create(building2)

      HierarchyValkeyImpl.link_child(company, property1)
      HierarchyValkeyImpl.link_child(company, property2)
      HierarchyValkeyImpl.link_child(property1, building1)
      HierarchyValkeyImpl.link_child(property2, building2)

      # Query all buildings under company (O(1) set query)
      {:ok, buildings} = HierarchyValkeyImpl.get_descendants_by_type("Company", 1001, :building)

      assert length(buildings) == 2
      assert Enum.any?(buildings, fn b -> b.id == 3001 end)
      assert Enum.any?(buildings, fn b -> b.id == 3002 end)

      # Query all properties under company
      {:ok, properties} = HierarchyValkeyImpl.get_descendants_by_type("Company", 1001, :property)

      assert length(properties) == 2
      assert Enum.any?(properties, fn p -> p.id == 2001 end)
      assert Enum.any?(properties, fn p -> p.id == 2002 end)
    end

    test "unlink_child removes from descendant sets" do
      {:ok, company} = HierarchyNode.new(%{id: 1001, name: "Acme Corp", type: :company, metadata: company_metadata()})
      {:ok, property} = HierarchyNode.new(%{id: 2001, name: "Property A", type: :property, metadata: property_metadata()})
      {:ok, building} = HierarchyNode.new(%{id: 3001, name: "Building 1", type: :building, metadata: building_metadata()})

      HierarchyValkeyImpl.create(company)
      HierarchyValkeyImpl.create(property)
      HierarchyValkeyImpl.create(building)

      HierarchyValkeyImpl.link_child(company, property)
      HierarchyValkeyImpl.link_child(property, building)

      # Verify sets are populated
      {:ok, company_buildings_before} = Redix.command(:redix, ["SMEMBERS", "descendants:C#1001:building"])
      assert "B#3001" in company_buildings_before

      # Unlink property from company
      HierarchyValkeyImpl.unlink_child("Company", 1001, "Property", 2001)

      # Company should no longer have property or building in its sets
      {:ok, company_properties} = Redix.command(:redix, ["SMEMBERS", "descendants:C#1001:property"])
      assert "PR#2001" not in company_properties

      {:ok, company_buildings_after} = Redix.command(:redix, ["SMEMBERS", "descendants:C#1001:building"])
      assert "B#3001" not in company_buildings_after

      # Property should still have building in its set (we only unlinked property from company)
      {:ok, property_buildings} = Redix.command(:redix, ["SMEMBERS", "descendants:PR#2001:building"])
      assert "B#3001" in property_buildings
    end
  end
end
