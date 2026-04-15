defmodule Agentelic.Pipeline.TesterTest do
  use ExUnit.Case, async: true

  alias Agentelic.Pipeline.Tester
  alias Agentelic.Testing.DSL

  describe "run/3" do
    test "runs test cases against a simulated artifact" do
      test_cases = [
        %{
          name: "basic response test",
          given: "User says hello",
          expected: "Agent responds with greeting",
          mocks: [],
          assertions: [{:not_contains, "error"}],
          timeout_ms: 5000
        }
      ]

      artifact = %{path: "/tmp/test_build", hash: "abc123"}

      assert {:ok, test_run} = Tester.run(artifact, test_cases)

      assert test_run.total_tests == 1
      assert test_run.passed_tests + test_run.failed_tests + test_run.error_tests == 1
      assert is_integer(test_run.duration_ms)
      assert length(test_run.results) == 1
    end

    test "handles multiple test cases" do
      test_cases = [
        %{
          name: "test 1",
          given: "Input 1",
          expected: "Output 1",
          mocks: [],
          assertions: [{:not_contains, "secret"}],
          timeout_ms: 5000
        },
        %{
          name: "test 2",
          given: "Input 2",
          expected: "Output 2",
          mocks: [],
          assertions: [{:not_contains, "secret"}],
          timeout_ms: 5000
        },
        %{
          name: "test 3",
          given: "Input 3",
          expected: "Output 3",
          mocks: [
            %{tool_name: "lookup", match_args: %{}, return: %{result: "ok"}}
          ],
          assertions: [{:tool_not_called, "delete"}],
          timeout_ms: 5000
        }
      ]

      artifact = %{path: "/tmp/build", hash: "def456"}

      assert {:ok, test_run} = Tester.run(artifact, test_cases)

      assert test_run.total_tests == 3
      assert length(test_run.results) == 3

      # All results have required fields
      for result <- test_run.results do
        assert Map.has_key?(result, :test_name)
        assert Map.has_key?(result, :status)
        assert Map.has_key?(result, :duration_ms)
        assert result.status in [:passed, :failed, :error]
      end
    end

    test "produces correct pass/fail counts" do
      # Tool_called assertions will fail because the simulated agent makes no tool calls
      test_cases = [
        %{
          name: "will pass — not_contains on empty output",
          given: "Input",
          expected: "Output",
          mocks: [],
          assertions: [{:not_contains, "secret"}],
          timeout_ms: 5000
        },
        %{
          name: "will fail — expects tool call but none made",
          given: "Input",
          expected: "Output",
          mocks: [],
          assertions: [{:tool_called, "orders:read", %{order_id: "123"}}],
          timeout_ms: 5000
        }
      ]

      artifact = %{path: "/tmp/build", hash: "ghi789"}

      assert {:ok, test_run} = Tester.run(artifact, test_cases)

      assert test_run.total_tests == 2
      assert test_run.passed_tests == 1
      assert test_run.failed_tests == 1
      assert test_run.status == :failed
    end

    test "test results include assertion details" do
      test_cases = [
        %{
          name: "assertion details test",
          given: "Some input",
          expected: "Some output",
          mocks: [],
          assertions: [
            {:not_contains, "forbidden_word"},
            {:tool_not_called, "dangerous_tool"}
          ],
          timeout_ms: 5000
        }
      ]

      artifact = %{path: "/tmp/build", hash: "jkl012"}

      {:ok, test_run} = Tester.run(artifact, test_cases)

      [result] = test_run.results
      assert length(result.assertions) == 2

      for assertion <- result.assertions do
        assert Map.has_key?(assertion, :type)
        assert Map.has_key?(assertion, :passed)
      end
    end

    test "handles empty test case list" do
      assert {:ok, test_run} = Tester.run(%{}, [])

      assert test_run.total_tests == 0
      assert test_run.passed_tests == 0
      assert test_run.failed_tests == 0
      assert test_run.status == :passed
    end

    test "works with DSL-generated test cases from spec" do
      spec_content = File.read!("test/fixtures/customer_support_spec.md")

      {:ok, spec} = Agentelic.Pipeline.Parser.parse(spec_content)
      test_cases = DSL.from_spec(spec)

      artifact = %{path: "/tmp/build", hash: "mno345"}

      assert {:ok, test_run} = Tester.run(artifact, test_cases)

      assert test_run.total_tests == length(test_cases)
      assert is_list(test_run.results)
    end
  end
end
