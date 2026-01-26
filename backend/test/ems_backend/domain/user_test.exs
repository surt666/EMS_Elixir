defmodule EmsBackend.Domain.UserTest do
  use ExUnit.Case, async: true

  alias EmsBackend.Domain.User

  describe "new/1" do
    test "creates a valid user" do
      attrs = %{
        email: "test@example.com",
        name: "Test User"
      }

      assert {:ok, user} = User.new(attrs)
      assert user.email == "test@example.com"
      assert user.name == "Test User"
      assert user.id == "U#test@example.com"
      assert user.profile == :reader
      assert user.language == :danish
      assert user.currency == :dkk
      assert %DateTime{} = user.created
    end

    test "validates email is required" do
      attrs = %{
        email: nil,
        name: "Test User"
      }

      assert {:error, "Email is required"} = User.new(attrs)
    end

    test "validates email format" do
      attrs = %{
        email: "invalid-email",
        name: "Test User"
      }

      assert {:error, "Invalid email format"} = User.new(attrs)
    end

    test "validates name is required" do
      attrs = %{
        email: "test@example.com",
        name: nil
      }

      assert {:error, "Name is required"} = User.new(attrs)
    end

    test "accepts custom profile, language, and currency" do
      attrs = %{
        email: "admin@example.com",
        name: "Admin User",
        profile: :admin,
        language: :english,
        currency: :eur
      }

      assert {:ok, user} = User.new(attrs)
      assert user.profile == :admin
      assert user.language == :english
      assert user.currency == :eur
    end
  end

  describe "promote_to_writer/1" do
    test "promotes reader to writer" do
      {:ok, user} = User.new(%{email: "test@example.com", name: "Test"})

      assert {:ok, promoted} = User.promote_to_writer(user)
      assert promoted.profile == :writer
    end

    test "cannot promote non-reader" do
      {:ok, user} = User.new(%{email: "test@example.com", name: "Test", profile: :writer})

      assert {:error, "Cannot promote user with profile: writer"} = User.promote_to_writer(user)
    end
  end

  describe "promote_to_admin/1" do
    test "promotes writer to admin" do
      {:ok, user} = User.new(%{email: "test@example.com", name: "Test", profile: :writer})

      assert {:ok, promoted} = User.promote_to_admin(user)
      assert promoted.profile == :admin
    end

    test "cannot promote reader directly to admin" do
      {:ok, user} = User.new(%{email: "test@example.com", name: "Test"})

      assert {:error, "Cannot promote to admin from profile: reader"} =
               User.promote_to_admin(user)
    end
  end

  describe "demote/1" do
    test "demotes admin to writer" do
      {:ok, user} = User.new(%{email: "test@example.com", name: "Test", profile: :admin})

      assert {:ok, demoted} = User.demote(user)
      assert demoted.profile == :writer
    end

    test "demotes writer to reader" do
      {:ok, user} = User.new(%{email: "test@example.com", name: "Test", profile: :writer})

      assert {:ok, demoted} = User.demote(user)
      assert demoted.profile == :reader
    end

    test "cannot demote reader" do
      {:ok, user} = User.new(%{email: "test@example.com", name: "Test"})

      assert {:error, "Cannot demote reader profile"} = User.demote(user)
    end
  end

  describe "admin?/1 and can_write?/1" do
    test "admin? returns true for admins" do
      {:ok, user} = User.new(%{email: "test@example.com", name: "Test", profile: :admin})

      assert User.admin?(user) == true
    end

    test "admin? returns false for non-admins" do
      {:ok, user} = User.new(%{email: "test@example.com", name: "Test", profile: :writer})

      assert User.admin?(user) == false
    end

    test "can_write? returns true for admins and writers" do
      {:ok, admin} = User.new(%{email: "admin@example.com", name: "Admin", profile: :admin})
      {:ok, writer} = User.new(%{email: "writer@example.com", name: "Writer", profile: :writer})

      assert User.can_write?(admin) == true
      assert User.can_write?(writer) == true
    end

    test "can_write? returns false for readers" do
      {:ok, reader} = User.new(%{email: "reader@example.com", name: "Reader", profile: :reader})

      assert User.can_write?(reader) == false
    end
  end

  describe "set_hierarchy_access/2" do
    test "sets hierarchy access permissions" do
      {:ok, user} = User.new(%{email: "test@example.com", name: "Test"})

      access = %{
        node_id: 1001,
        permission: :write,
        node_type: "Company"
      }

      assert {:ok, updated} = User.set_hierarchy_access(user, access)
      assert updated.hierarchy_access == access
    end
  end

  describe "update_preferences/2" do
    test "updates language and currency" do
      {:ok, user} = User.new(%{email: "test@example.com", name: "Test"})

      assert {:ok, updated} = User.update_preferences(user, %{language: :english, currency: :usd})
      assert updated.language == :english
      assert updated.currency == :usd
    end

    test "keeps existing preferences if not provided" do
      {:ok, user} = User.new(%{email: "test@example.com", name: "Test", language: :danish})

      assert {:ok, updated} = User.update_preferences(user, %{currency: :eur})
      assert updated.language == :danish
      assert updated.currency == :eur
    end
  end
end
