defmodule EmsBackend.HierarchyFixtures do
  @moduledoc """
  Shared test fixtures for hierarchy nodes with proper metadata.
  """

  def root_metadata do
    %{}
  end

  def partner_metadata do
    %{
      email: "partner@example.com",
      address: %{zip: 2000, street: "Partner St", country: "Denmark", nr: 1},
      phone: %{country_code: "+45", number: "87654321"}
    }
  end

  def company_metadata do
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

  def property_metadata do
    %{
      location: %{lat: 55.6761, long: 12.5683},
      address: %{zip: 3000, street: "Property Ave", country: "Denmark", nr: 50},
      usage: "Commercial",
      bbr: "54321",
      weather_station: "DMI_COPENHAGEN"
    }
  end

  def building_metadata do
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

  def area_metadata do
    %{name: "Ground Floor"}
  end

  def group_metadata do
    %{name: "Building Group A"}
  end
end
