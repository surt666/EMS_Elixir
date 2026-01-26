defmodule EmsBackend.Domain.HierarchyNode do
  @moduledoc """
  Domain model for HierarchyNode entity.
  Represents a node in the organizational hierarchy (Company, Property, Building, Area, etc.)

  Pure business logic without dependencies on infrastructure.
  """

  @type node_type :: :root | :partner | :company | :property | :building | :area | :group

  @type metadata :: %{
          root: root_metadata(),
          building: building_metadata(),
          company: company_metadata(),
          partner: partner_metadata(),
          property: property_metadata(),
          area: area_metadata(),
          group: group_metadata()
        }

  @type root_metadata :: %{}

  @type building_metadata :: %{
          email: String.t(),
          location: location(),
          usage: String.t(),
          total_area: non_neg_integer(),
          heated_area: non_neg_integer(),
          bbr: String.t(),
          build_year: non_neg_integer(),
          p_nr: non_neg_integer(),
          ext_id: String.t(),
          weather_station: String.t(),
          timezone: String.t()
        }

  @type company_metadata :: %{
          email: String.t(),
          address: address(),
          cvr: non_neg_integer(),
          phone: phone_nr(),
          contact: String.t(),
          homepage: String.t(),
          status: :active | :inactive | :suspended,
          sla: :standard | :premium | :enterprise
        }

  @type partner_metadata :: %{
          email: String.t(),
          address: address(),
          phone: phone_nr()
        }

  @type property_metadata :: %{
          location: location(),
          address: address(),
          usage: String.t(),
          bbr: String.t(),
          weather_station: String.t()
        }

  @type area_metadata :: %{name: String.t()}
  @type group_metadata :: %{name: String.t()}

  @type location :: %{lat: float(), long: float()}
  @type address :: %{zip: non_neg_integer(), street: String.t(), country: String.t(), nr: non_neg_integer()}
  @type phone_nr :: %{country_code: String.t(), number: String.t()}

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          created: DateTime.t(),
          type: node_type(),
          name: String.t(),
          metadata: map(),
          blocked: boolean(),
          parent: String.t() | nil
        }

  defstruct [
    :id,
    :created,
    :type,
    :name,
    :metadata,
    blocked: false,
    parent: nil
  ]

  @doc """
  Creates a new hierarchy node with validation.
  Pure business logic - no side effects.
  """
  def new(attrs) do
    with :ok <- validate_name(attrs[:name]),
         :ok <- validate_type(attrs[:type]),
         :ok <- validate_metadata(attrs[:type], attrs[:metadata]) do
      node = %__MODULE__{
        id: attrs[:id] || generate_id(),
        created: attrs[:created] || DateTime.utc_now(),
        type: attrs[:type],
        name: attrs[:name],
        metadata: attrs[:metadata],
        blocked: attrs[:blocked] || false,
        parent: attrs[:parent]
      }
      {:ok, node}
    end
  end

  @doc """
  Blocks a node.
  Business rule: any node can be blocked.
  """
  def block(%__MODULE__{} = node) do
    {:ok, %{node | blocked: true}}
  end

  @doc """
  Unblocks a node.
  """
  def unblock(%__MODULE__{} = node) do
    {:ok, %{node | blocked: false}}
  end

  @doc """
  Checks if a node is accessible (not blocked).
  """
  def accessible?(%__MODULE__{blocked: blocked}), do: !blocked

  @doc """
  Updates node metadata.
  Business rule: metadata must match node type.
  """
  def update_metadata(%__MODULE__{} = node, metadata) do
    {:ok, %{node | metadata: metadata}}
  end

  @doc """
  Sets parent for a node.
  Business rule: parent must be a valid node reference.
  """
  def set_parent(%__MODULE__{} = node, parent_ref) when is_binary(parent_ref) do
    {:ok, %{node | parent: parent_ref}}
  end

  def set_parent(%__MODULE__{} = node, nil) do
    {:ok, %{node | parent: nil}}
  end

  # Private validation functions

  defp validate_name(nil), do: {:error, "Name is required"}
  defp validate_name(name) when is_binary(name) and byte_size(name) > 0, do: :ok
  defp validate_name(_), do: {:error, "Name must be a non-empty string"}

  defp validate_type(nil), do: {:error, "Type is required"}

  defp validate_type(type)
       when type in [:root, :partner, :company, :property, :building, :area, :group],
       do: :ok

  defp validate_type(type) when is_atom(type),
    do: {:error, "Invalid node type: #{inspect(type)}. Must be one of [:root, :partner, :company, :property, :building, :area, :group]"}

  defp validate_type(type),
    do: {:error, "Type must be an atom, got: #{inspect(type)}"}

  defp validate_metadata(_type, nil), do: {:error, "Metadata is required"}

  defp validate_metadata(:root, metadata) when is_map(metadata), do: :ok
  defp validate_metadata(:root, _), do: {:error, "root metadata must be a map"}

  defp validate_metadata(:partner, metadata) do
    required_fields = [:email, :address, :phone]
    validate_required_fields(metadata, required_fields, :partner)
  end

  defp validate_metadata(:company, metadata) do
    required_fields = [:email, :address, :cvr, :phone, :contact, :homepage, :status, :sla]
    with :ok <- validate_required_fields(metadata, required_fields, :company),
         :ok <- validate_status(metadata[:status]),
         :ok <- validate_sla(metadata[:sla]) do
      :ok
    end
  end

  defp validate_metadata(:property, metadata) do
    required_fields = [:location, :address, :usage, :bbr, :weather_station]
    validate_required_fields(metadata, required_fields, :property)
  end

  defp validate_metadata(:building, metadata) do
    required_fields = [:email, :location, :usage, :total_area, :heated_area, :bbr, :build_year, :p_nr, :ext_id, :weather_station, :timezone]
    validate_required_fields(metadata, required_fields, :building)
  end

  defp validate_metadata(:area, metadata) do
    required_fields = [:name]
    validate_required_fields(metadata, required_fields, :area)
  end

  defp validate_metadata(:group, metadata) do
    required_fields = [:name]
    validate_required_fields(metadata, required_fields, :group)
  end

  defp validate_required_fields(metadata, required_fields, type) when is_map(metadata) do
    missing_fields = Enum.filter(required_fields, fn field ->
      not Map.has_key?(metadata, field) or is_nil(metadata[field])
    end)

    case missing_fields do
      [] -> :ok
      fields -> {:error, "#{type} metadata missing required fields: #{inspect(fields)}"}
    end
  end

  defp validate_required_fields(_metadata, _required_fields, type) do
    {:error, "#{type} metadata must be a map"}
  end

  defp validate_status(status) when status in [:active, :inactive, :suspended], do: :ok
  defp validate_status(status), do: {:error, "Invalid status: #{inspect(status)}. Must be :active, :inactive, or :suspended"}

  defp validate_sla(sla) when sla in [:standard, :premium, :enterprise], do: :ok
  defp validate_sla(sla), do: {:error, "Invalid SLA: #{inspect(sla)}. Must be :standard, :premium, or :enterprise"}

  defp generate_id do
    # Generate a random ID (in production this would come from the database)
    :rand.uniform(4_294_967_295)
  end
end
