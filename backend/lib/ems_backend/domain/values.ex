defmodule EmsBackend.Domain.Values do
  @moduledoc """
  Domain value types for the EMS system.

  Contains enums for timezone, profile, language, currency, permission, and node types.
  These are used for validation and generating HTML select options for HTMX responses.
  """

  # Node types in the hierarchy
  @node_types [:root, :partner, :company, :property, :building, :area, :group]

  # Timezones commonly used
  @timezones [
    "Europe/Copenhagen",
    "Europe/London",
    "Europe/Paris",
    "Europe/Berlin",
    "Europe/Stockholm",
    "Europe/Oslo",
    "Europe/Helsinki",
    "Europe/Amsterdam",
    "Europe/Brussels",
    "Europe/Vienna",
    "Europe/Warsaw",
    "Europe/Prague",
    "Europe/Madrid",
    "Europe/Rome",
    "Europe/Athens",
    "America/New_York",
    "America/Chicago",
    "America/Denver",
    "America/Los_Angeles",
    "America/Toronto",
    "America/Vancouver",
    "Asia/Tokyo",
    "Asia/Shanghai",
    "Asia/Singapore",
    "Asia/Hong_Kong",
    "Asia/Dubai",
    "Australia/Sydney",
    "Australia/Melbourne",
    "Pacific/Auckland",
    "UTC"
  ]

  # User profiles/roles
  @profiles [:admin, :writer, :reader]

  # Supported languages
  @languages [:da, :en, :de, :sv, :no, :fi, :nl, :fr, :es, :it, :pl, :cs]

  # Supported currencies
  @currencies [:DKK, :EUR, :USD, :GBP, :SEK, :NOK, :CHF, :PLN, :CZK]

  # Permission levels
  @permissions [:read, :write, :admin, :blocked]

  # Company status
  @company_statuses [:active, :inactive, :suspended]

  # SLA levels
  @sla_levels [:standard, :premium, :enterprise]

  # Getters for each enum
  def node_types, do: @node_types
  def timezones, do: @timezones
  def profiles, do: @profiles
  def languages, do: @languages
  def currencies, do: @currencies
  def permissions, do: @permissions
  def company_statuses, do: @company_statuses
  def sla_levels, do: @sla_levels

  @doc """
  Generates HTML <option> elements for a list of values.
  Returns a string of HTML options suitable for HTMX responses.
  """
  def to_html_options(values) when is_list(values) do
    values
    |> Enum.map(fn value ->
      str_value = value_to_string(value)
      ~s(<option value="#{str_value}">#{str_value}</option>)
    end)
    |> Enum.join("")
  end

  @doc """
  Generates HTML <option> elements for timezones.
  """
  def timezones_html, do: to_html_options(@timezones)

  @doc """
  Generates HTML <option> elements for profiles.
  """
  def profiles_html, do: to_html_options(@profiles)

  @doc """
  Generates HTML <option> elements for languages.
  """
  def languages_html, do: to_html_options(@languages)

  @doc """
  Generates HTML <option> elements for currencies.
  """
  def currencies_html, do: to_html_options(@currencies)

  @doc """
  Generates HTML <option> elements for permissions.
  """
  def permissions_html, do: to_html_options(@permissions)

  @doc """
  Generates HTML <option> elements for node types.
  """
  def node_types_html, do: to_html_options(@node_types)

  # Convert value to string representation
  defp value_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp value_to_string(value) when is_binary(value), do: value
  defp value_to_string(value), do: to_string(value)

  @doc """
  Parses a string into a profile atom.
  """
  def parse_profile(str) when is_binary(str) do
    atom = String.to_existing_atom(String.downcase(str))
    if atom in @profiles, do: {:ok, atom}, else: {:error, :invalid_profile}
  rescue
    ArgumentError -> {:error, :invalid_profile}
  end
  def parse_profile(atom) when atom in @profiles, do: {:ok, atom}
  def parse_profile(_), do: {:error, :invalid_profile}

  @doc """
  Parses a string into a permission atom.
  """
  def parse_permission(str) when is_binary(str) do
    atom = String.to_existing_atom(String.downcase(str))
    if atom in @permissions, do: {:ok, atom}, else: {:error, :invalid_permission}
  rescue
    ArgumentError -> {:error, :invalid_permission}
  end
  def parse_permission(atom) when atom in @permissions, do: {:ok, atom}
  def parse_permission(_), do: {:error, :invalid_permission}

  @doc """
  Parses a string into a language atom.
  """
  def parse_language(str) when is_binary(str) do
    atom = String.to_existing_atom(String.downcase(str))
    if atom in @languages, do: {:ok, atom}, else: {:error, :invalid_language}
  rescue
    ArgumentError -> {:error, :invalid_language}
  end
  def parse_language(atom) when atom in @languages, do: {:ok, atom}
  def parse_language(_), do: {:error, :invalid_language}

  @doc """
  Parses a string into a currency atom.
  """
  def parse_currency(str) when is_binary(str) do
    atom = String.to_existing_atom(String.upcase(str))
    if atom in @currencies, do: {:ok, atom}, else: {:error, :invalid_currency}
  rescue
    ArgumentError -> {:error, :invalid_currency}
  end
  def parse_currency(atom) when atom in @currencies, do: {:ok, atom}
  def parse_currency(_), do: {:error, :invalid_currency}

  @doc """
  Parses a string into a node type atom.
  """
  def parse_node_type(str) when is_binary(str) do
    atom = String.to_existing_atom(String.downcase(str))
    if atom in @node_types, do: {:ok, atom}, else: {:error, :invalid_node_type}
  rescue
    ArgumentError -> {:error, :invalid_node_type}
  end
  def parse_node_type(atom) when atom in @node_types, do: {:ok, atom}
  def parse_node_type(_), do: {:error, :invalid_node_type}
end
