defmodule Agentelic.Pipeline.TestIntakeTest do
  use ExUnit.Case, async: true

  alias Agentelic.Pipeline.TestIntake

  @compiled_tests_path "test/fixtures/compiled_tests.json"

  setup do
    json = File.read!(@compiled_tests_path)
    {:ok, json: json}
  end

  describe "load/2" do
    test "loads approved compiled tests from JSON", %{json: json} do
      spec = %{acceptance_tests: [], capabilities: [], constraints: []}

      assert {:ok, test_cases, hash} = TestIntake.load(spec, compiled_tests: json)

      # Only approved tests should be loaded (3 of 4 in fixture)
      assert length(test_cases) == 3
      assert is_binary(hash)
    end

    test "filters out unapproved tests", %{json: json} do
      spec = %{acceptance_tests: [], capabilities: [], constraints: []}

      {:ok, test_cases, _hash} = TestIntake.load(spec, compiled_tests: json)

      names = Enum.map(test_cases, & &1.name)
      refute "never reveals internal pricing (unapproved)" in names
    end

    test "converts assertions to DSL format", %{json: json} do
      spec = %{acceptance_tests: [], capabilities: [], constraints: []}

      {:ok, [first | _], _hash} = TestIntake.load(spec, compiled_tests: json)

      assert Enum.any?(first.assertions, fn
               {:contains, _} -> true
               _ -> false
             end)
    end

    test "computes deterministic hash", %{json: json} do
      spec = %{acceptance_tests: [], capabilities: [], constraints: []}

      {:ok, _, hash1} = TestIntake.load(spec, compiled_tests: json)
      {:ok, _, hash2} = TestIntake.load(spec, compiled_tests: json)

      assert hash1 == hash2
    end

    test "falls back to spec-generated tests when no compiled tests" do
      spec = %{
        acceptance_tests: [%{given: "test input", expected: "test output"}],
        capabilities: [],
        constraints: []
      }

      assert {:ok, test_cases, _hash} = TestIntake.load(spec)
      assert length(test_cases) == 1
    end
  end
end
