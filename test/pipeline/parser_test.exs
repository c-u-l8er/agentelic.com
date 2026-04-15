defmodule Agentelic.Pipeline.ParserTest do
  use ExUnit.Case, async: true

  alias Agentelic.Pipeline.Parser

  @fixture_path "test/fixtures/customer_support_spec.md"

  setup do
    spec_content = File.read!(@fixture_path)
    {:ok, spec_content: spec_content}
  end

  describe "parse/1" do
    test "parses a valid SPEC.md into structured spec", %{spec_content: content} do
      assert {:ok, spec} = Parser.parse(content)

      assert spec.name == "Customer Support Agent"
      assert spec.version == "1.0.0"
      assert is_binary(spec.spec_hash)
      assert String.length(spec.spec_hash) == 64
    end

    test "extracts capabilities from spec", %{spec_content: content} do
      {:ok, spec} = Parser.parse(content)

      assert length(spec.capabilities) > 0
      cap_names = Enum.map(spec.capabilities, & &1.name)
      assert "orders:read" in cap_names or Enum.any?(cap_names, &String.contains?(&1, "orders"))
    end

    test "extracts constraints from spec", %{spec_content: content} do
      {:ok, spec} = Parser.parse(content)

      assert length(spec.constraints) > 0

      descriptions = Enum.map(spec.constraints, & &1.description)

      assert Enum.any?(descriptions, &String.contains?(&1, "pricing"))
    end

    test "extracts acceptance tests from spec", %{spec_content: content} do
      {:ok, spec} = Parser.parse(content)

      assert length(spec.acceptance_tests) > 0
    end

    test "computes deterministic spec_hash", %{spec_content: content} do
      {:ok, spec1} = Parser.parse(content)
      {:ok, spec2} = Parser.parse(content)

      assert spec1.spec_hash == spec2.spec_hash
    end

    test "different content produces different hash" do
      {:ok, spec1} =
        Parser.parse(
          "# Spec A\n\n## Executive Summary\nA\n## Architecture\nB\n## Acceptance Tests\nC"
        )

      {:ok, spec2} =
        Parser.parse(
          "# Spec B\n\n## Executive Summary\nX\n## Architecture\nY\n## Acceptance Tests\nZ"
        )

      assert spec1.spec_hash != spec2.spec_hash
    end
  end

  describe "compute_hash/1" do
    test "returns SHA-256 hex string" do
      hash = Parser.compute_hash("hello")
      assert String.length(hash) == 64
      assert Regex.match?(~r/^[0-9a-f]+$/, hash)
    end

    test "is deterministic" do
      assert Parser.compute_hash("test") == Parser.compute_hash("test")
    end
  end
end
