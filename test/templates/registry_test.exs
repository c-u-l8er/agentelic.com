defmodule Agentelic.Templates.RegistryTest do
  use ExUnit.Case, async: true

  alias Agentelic.Templates.{Registry, Manifest}

  describe "Manifest.validate/1" do
    test "validates a complete manifest" do
      manifest = %{
        "name" => "elixir/mcp-server",
        "version" => "1.0.0",
        "framework" => "elixir",
        "product_type" => "mcp_server"
      }

      assert :ok = Manifest.validate(manifest)
    end

    test "rejects manifest with missing required fields" do
      assert {:error, errors} = Manifest.validate(%{})
      assert Enum.any?(errors, &String.contains?(&1, "Missing required"))
    end

    test "rejects invalid framework" do
      manifest = %{
        "name" => "test",
        "version" => "1.0.0",
        "framework" => "cobol",
        "product_type" => "agent"
      }

      assert {:error, errors} = Manifest.validate(manifest)
      assert Enum.any?(errors, &String.contains?(&1, "Invalid framework"))
    end

    test "rejects invalid version format" do
      manifest = %{
        "name" => "test",
        "version" => "not-a-version",
        "framework" => "elixir",
        "product_type" => "agent"
      }

      assert {:error, errors} = Manifest.validate(manifest)
      assert Enum.any?(errors, &String.contains?(&1, "Invalid version"))
    end
  end

  describe "Registry.list/1" do
    test "returns a list of templates" do
      templates = Registry.list()
      assert is_list(templates)
    end

    test "filters by framework" do
      templates = Registry.list(framework: "elixir")

      for t <- templates do
        assert t.framework == "elixir"
      end
    end
  end
end
