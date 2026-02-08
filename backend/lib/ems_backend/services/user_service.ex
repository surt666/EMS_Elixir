defmodule EmsBackend.Services.UserService do
  @moduledoc """
  Service for managing users.

  Handles user creation, retrieval, and listing.
  Users are stored in Valkey with key pattern: user:{email}
  """

  alias EmsBackend.Domain.User

  @doc """
  Creates and stores a new user.

  ## Examples

      iex> create(%{email: "user@example.com", name: "John Doe"})
      {:ok, %User{}}
  """
  def create(attrs) do
    with {:ok, user} <- User.new(attrs),
         :ok <- store_user(user) do
      {:ok, user}
    end
  end

  @doc """
  Gets a user by email.

  ## Examples

      iex> get("user@example.com")
      {:ok, %User{}}

      iex> get("unknown@example.com")
      {:error, :not_found}
  """
  def get(email) do
    key = user_key(email)

    case Redix.command(:redix, ["GET", key]) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, data} -> {:ok, deserialize_user(data)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists all users.

  ## Examples

      iex> list()
      {:ok, [%User{}, ...]}
  """
  def list do
    case Redix.command(:redix, ["KEYS", "user:*"]) do
      {:ok, keys} ->
        users =
          keys
          |> Enum.map(fn key ->
            case Redix.command(:redix, ["GET", key]) do
              {:ok, data} when not is_nil(data) -> deserialize_user(data)
              _ -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        {:ok, users}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes a user by email.

  ## Examples

      iex> delete("user@example.com")
      :ok
  """
  def delete(email) do
    key = user_key(email)

    case Redix.command(:redix, ["DEL", key]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Updates a user's attributes.

  ## Examples

      iex> update("user@example.com", %{name: "New Name"})
      {:ok, %User{}}
  """
  def update(email, attrs) do
    with {:ok, user} <- get(email) do
      updated_user = %{user |
        name: attrs[:name] || user.name,
        profile: attrs[:profile] || user.profile,
        language: attrs[:language] || user.language,
        currency: attrs[:currency] || user.currency
      }

      with :ok <- store_user(updated_user) do
        {:ok, updated_user}
      end
    end
  end

  # Private helpers

  defp user_key(email), do: "user:#{email}"

  defp store_user(user) do
    key = user_key(user.email)
    data = serialize_user(user)

    case Redix.command(:redix, ["SET", key, data]) do
      {:ok, "OK"} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp serialize_user(user) do
    %{
      id: user.id,
      email: user.email,
      name: user.name,
      profile: Atom.to_string(user.profile),
      language: Atom.to_string(user.language),
      currency: Atom.to_string(user.currency),
      created: DateTime.to_iso8601(user.created)
    }
    |> Msgpax.pack!(iodata: false)
  end

  defp deserialize_user(data) do
    {:ok, map} = Msgpax.unpack(data)
    {:ok, created, _} = DateTime.from_iso8601(map["created"])

    %User{
      id: map["id"],
      email: map["email"],
      name: map["name"],
      profile: to_profile(map["profile"]),
      language: to_language(map["language"]),
      currency: to_currency(map["currency"]),
      created: created
    }
  end

  defp to_profile("admin"), do: :admin
  defp to_profile("writer"), do: :writer
  defp to_profile("reader"), do: :reader
  defp to_profile(_), do: :reader

  defp to_language("danish"), do: :danish
  defp to_language("swedish"), do: :swedish
  defp to_language("norwegian"), do: :norwegian
  defp to_language("english"), do: :english
  defp to_language("german"), do: :german
  defp to_language(_), do: :english

  defp to_currency("dkk"), do: :dkk
  defp to_currency("sek"), do: :sek
  defp to_currency("nok"), do: :nok
  defp to_currency("usd"), do: :usd
  defp to_currency("eur"), do: :eur
  defp to_currency(_), do: :dkk
end
