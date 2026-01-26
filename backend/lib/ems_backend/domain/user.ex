defmodule EmsBackend.Domain.User do
  @moduledoc """
  Domain model for User entity.
  Contains pure business logic without dependencies on infrastructure.
  """

  @type profile :: :admin | :writer | :reader
  @type language :: :danish | :swedish | :norwegian | :english | :german
  @type currency :: :dkk | :sek | :nok | :usd | :eur

  @type node_permission :: %{
          node_id: non_neg_integer(),
          permission: :read | :write | :admin | :blocked,
          node_type: String.t()
        }

  @type t :: %__MODULE__{
          id: String.t(),
          email: String.t(),
          name: String.t(),
          profile: profile(),
          language: language(),
          currency: currency(),
          hierarchy_access: node_permission() | nil,
          created: DateTime.t()
        }

  defstruct [
    :id,
    :email,
    :name,
    profile: :reader,
    language: :danish,
    currency: :dkk,
    hierarchy_access: nil,
    created: nil
  ]

  @doc """
  Creates a new user with validation.
  Pure business logic - no side effects.
  """
  def new(attrs) do
    with :ok <- validate_email(attrs[:email]),
         :ok <- validate_name(attrs[:name]) do
      user = %__MODULE__{
        id: attrs[:id] || generate_user_id(attrs[:email]),
        email: attrs[:email],
        name: attrs[:name],
        profile: attrs[:profile] || :reader,
        language: attrs[:language] || :danish,
        currency: attrs[:currency] || :dkk,
        hierarchy_access: attrs[:hierarchy_access],
        created: attrs[:created] || DateTime.utc_now()
      }
      {:ok, user}
    end
  end

  @doc """
  Promotes a user to writer profile.
  Business rule: readers can be promoted to writers.
  """
  def promote_to_writer(%__MODULE__{profile: :reader} = user) do
    {:ok, %{user | profile: :writer}}
  end

  def promote_to_writer(%__MODULE__{profile: profile}) do
    {:error, "Cannot promote user with profile: #{profile}"}
  end

  @doc """
  Promotes a user to admin profile.
  Business rule: only writers can be promoted to admins.
  """
  def promote_to_admin(%__MODULE__{profile: :writer} = user) do
    {:ok, %{user | profile: :admin}}
  end

  def promote_to_admin(%__MODULE__{profile: profile}) do
    {:error, "Cannot promote to admin from profile: #{profile}"}
  end

  @doc """
  Demotes a user profile.
  Business rule: admins can be demoted to writers, writers to readers.
  """
  def demote(%__MODULE__{profile: :admin} = user) do
    {:ok, %{user | profile: :writer}}
  end

  def demote(%__MODULE__{profile: :writer} = user) do
    {:ok, %{user | profile: :reader}}
  end

  def demote(%__MODULE__{profile: :reader}) do
    {:error, "Cannot demote reader profile"}
  end

  @doc """
  Checks if user has admin privileges.
  """
  def admin?(%__MODULE__{profile: :admin}), do: true
  def admin?(%__MODULE__{}), do: false

  @doc """
  Checks if user can write.
  """
  def can_write?(%__MODULE__{profile: profile}) when profile in [:admin, :writer], do: true
  def can_write?(%__MODULE__{}), do: false

  @doc """
  Sets hierarchy access permissions for the user.
  """
  def set_hierarchy_access(%__MODULE__{} = user, node_permission) do
    {:ok, %{user | hierarchy_access: node_permission}}
  end

  @doc """
  Updates user preferences (language, currency).
  """
  def update_preferences(%__MODULE__{} = user, attrs) do
    user = %{user |
      language: attrs[:language] || user.language,
      currency: attrs[:currency] || user.currency
    }
    {:ok, user}
  end

  # Private validation functions

  defp validate_email(nil), do: {:error, "Email is required"}

  defp validate_email(email) when is_binary(email) do
    if String.contains?(email, "@") do
      :ok
    else
      {:error, "Invalid email format"}
    end
  end

  defp validate_email(_), do: {:error, "Email must be a string"}

  defp validate_name(nil), do: {:error, "Name is required"}
  defp validate_name(name) when is_binary(name) and byte_size(name) > 0, do: :ok
  defp validate_name(_), do: {:error, "Name must be a non-empty string"}

  defp generate_user_id(email) do
    "U##{email}"
  end
end
