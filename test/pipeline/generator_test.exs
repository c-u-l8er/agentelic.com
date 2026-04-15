defmodule Agentelic.Pipeline.GeneratorTest do
  use ExUnit.Case, async: true

  alias Agentelic.Pipeline.{Parser, Generator}

  @spec_fixture "test/fixtures/customer_support_spec.md"

  describe "generate/2" do
    test "generates files from spec with default elixir/mcp_server template" do
      spec_content = File.read!(@spec_fixture)
      {:ok, spec} = Parser.parse(spec_content)

      assert {:ok, files, template_info} =
               Generator.generate(spec, framework: "elixir", product_type: :mcp_server)

      assert is_list(files)
      assert length(files) > 0

      # Each file has path and content
      for file <- files do
        assert is_binary(file.path)
        assert is_binary(file.content)
        refute String.ends_with?(file.path, ".eex")
      end

      # Template info includes version and hash
      assert is_binary(template_info.name)
      assert is_binary(template_info.version)
      assert is_binary(template_info.hash)
    end

    test "generates typescript files when framework is typescript" do
      spec_content = File.read!(@spec_fixture)
      {:ok, spec} = Parser.parse(spec_content)

      assert {:ok, files, template_info} =
               Generator.generate(spec, framework: "typescript", product_type: :mcp_server)

      assert length(files) > 0
      assert template_info.name =~ "typescript"

      # Should have TypeScript-specific files
      paths = Enum.map(files, & &1.path)
      assert Enum.any?(paths, &String.ends_with?(&1, ".ts"))
    end

    test "returns error for unknown framework/product_type combo" do
      spec_content = File.read!(@spec_fixture)
      {:ok, spec} = Parser.parse(spec_content)

      assert {:error, _reason} =
               Generator.generate(spec, framework: "rust", product_type: :mcp_server)
    end

    test "deterministic: same spec + same template → same files" do
      spec_content = File.read!(@spec_fixture)
      {:ok, spec} = Parser.parse(spec_content)

      {:ok, files1, info1} =
        Generator.generate(spec, framework: "elixir", product_type: :mcp_server)

      {:ok, files2, info2} =
        Generator.generate(spec, framework: "elixir", product_type: :mcp_server)

      # Same template hash
      assert info1.hash == info2.hash
      assert info1.version == info2.version

      # Same file contents
      contents1 = Enum.map(files1, & &1.content) |> Enum.sort()
      contents2 = Enum.map(files2, & &1.content) |> Enum.sort()
      assert contents1 == contents2
    end

    test "generated elixir files contain spec data" do
      spec_content = File.read!(@spec_fixture)
      {:ok, spec} = Parser.parse(spec_content)

      {:ok, files, _info} =
        Generator.generate(spec, framework: "elixir", product_type: :mcp_server)

      # The generated agent module should contain capability names
      agent_file = Enum.find(files, &String.contains?(&1.path, "agent.ex"))

      if agent_file do
        assert String.contains?(agent_file.content, "orders:read") or
                 String.contains?(agent_file.content, "orders_read") or
                 String.contains?(agent_file.content, "order")
      end
    end

    test "generated files respect pinned template version" do
      spec_content = File.read!(@spec_fixture)
      {:ok, spec} = Parser.parse(spec_content)

      {:ok, _files, info} =
        Generator.generate(spec,
          framework: "elixir",
          product_type: :mcp_server,
          template_pin: "0.1.0"
        )

      assert info.version == "0.1.0"
    end

    test "returns error for invalid template pin" do
      spec_content = File.read!(@spec_fixture)
      {:ok, spec} = Parser.parse(spec_content)

      assert {:error, _reason} =
               Generator.generate(spec,
                 framework: "elixir",
                 product_type: :mcp_server,
                 template_pin: "99.99.99"
               )
    end
  end
end
