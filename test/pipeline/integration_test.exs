defmodule Agentelic.Pipeline.IntegrationTest do
  use ExUnit.Case, async: true

  alias Agentelic.Pipeline.{Parser, TestIntake}
  alias Agentelic.Testing.DSL

  @spec_fixture "test/fixtures/customer_support_spec.md"
  @compiled_tests_fixture "test/fixtures/compiled_tests.json"

  describe "full pipeline parse → test intake flow" do
    test "parses spec and generates test cases from it" do
      spec_content = File.read!(@spec_fixture)

      assert {:ok, spec} = Parser.parse(spec_content)

      # Generate tests directly from spec
      test_cases = DSL.from_spec(spec)
      assert length(test_cases) > 0

      # Each case should be well-formed
      for tc <- test_cases do
        assert is_binary(tc.name)
        assert is_binary(tc.given)
        assert is_list(tc.mocks)
        assert is_list(tc.assertions)
        assert tc.timeout_ms > 0
      end
    end

    test "parses spec and loads compiled tests" do
      spec_content = File.read!(@spec_fixture)
      compiled_json = File.read!(@compiled_tests_fixture)

      assert {:ok, spec} = Parser.parse(spec_content)

      # Load compiled tests (only approved ones)
      assert {:ok, test_cases, hash} = TestIntake.load(spec, compiled_tests: compiled_json)

      # 3 of 4 fixture tests are approved
      assert length(test_cases) == 3
      assert is_binary(hash)

      # First test should have assertions
      [first | _] = test_cases
      assert first.name == "returns order status for valid order"
      assert length(first.assertions) > 0
      assert length(first.mocks) > 0
    end

    test "deterministic: same input produces same hashes" do
      spec_content = File.read!(@spec_fixture)
      compiled_json = File.read!(@compiled_tests_fixture)

      {:ok, spec1} = Parser.parse(spec_content)
      {:ok, spec2} = Parser.parse(spec_content)

      assert spec1.spec_hash == spec2.spec_hash

      {:ok, _, hash1} = TestIntake.load(spec1, compiled_tests: compiled_json)
      {:ok, _, hash2} = TestIntake.load(spec2, compiled_tests: compiled_json)

      assert hash1 == hash2
    end

    test "spec hash changes when content changes" do
      content1 = File.read!(@spec_fixture)
      content2 = content1 <> "\n## Extra Section\nNew content"

      {:ok, spec1} = Parser.parse(content1)
      {:ok, spec2} = Parser.parse(content2)

      refute spec1.spec_hash == spec2.spec_hash
    end
  end

  describe "test runner execution" do
    test "runs test cases and produces results" do
      spec_content = File.read!(@spec_fixture)
      compiled_json = File.read!(@compiled_tests_fixture)

      {:ok, spec} = Parser.parse(spec_content)
      {:ok, test_cases, _hash} = TestIntake.load(spec, compiled_tests: compiled_json)

      # Run tests (with simulated/mock agent — real agent not compiled yet)
      alias Agentelic.Testing.Runner

      assert {:ok, test_run} = Runner.execute(%{}, test_cases)

      assert test_run.total_tests == 3
      assert test_run.duration_ms >= 0
      assert is_list(test_run.results)
      assert length(test_run.results) == 3
    end
  end
end
