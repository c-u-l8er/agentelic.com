defmodule Agentelic.Testing.DSLTest do
  use ExUnit.Case, async: true

  alias Agentelic.Testing.DSL

  @sample_spec %{
    acceptance_tests: [
      %{
        given: "Customer asks about order #123",
        expected: "Agent responds with order status"
      },
      %{
        given: "Customer requests refund for $750",
        expected: "Agent escalates to human"
      }
    ],
    capabilities: [
      %{name: "orders:read", description: "Look up order status"},
      %{name: "returns:create", description: "Create a return"}
    ],
    constraints: [
      %{description: "Agent must not reveal internal pricing", type: :prohibition},
      %{description: "Agent should respond within 5 seconds", type: :recommendation}
    ]
  }

  describe "from_spec/1" do
    test "generates test cases from acceptance tests" do
      cases = DSL.from_spec(@sample_spec)

      assert length(cases) == 2
      assert Enum.all?(cases, &is_map/1)
    end

    test "each test case has required fields" do
      [first | _] = DSL.from_spec(@sample_spec)

      assert Map.has_key?(first, :name)
      assert Map.has_key?(first, :given)
      assert Map.has_key?(first, :expected)
      assert Map.has_key?(first, :mocks)
      assert Map.has_key?(first, :assertions)
      assert Map.has_key?(first, :timeout_ms)
      assert first.timeout_ms == 30_000
    end

    test "infers mocks from capabilities mentioned in test" do
      [order_test | _] = DSL.from_spec(@sample_spec)

      # The order test should infer an orders:read mock
      mock_names = Enum.map(order_test.mocks, & &1.tool_name)
      assert "orders:read" in mock_names
    end

    test "infers escalation assertions" do
      [_, escalation_test] = DSL.from_spec(@sample_spec)

      assertion_types =
        Enum.map(escalation_test.assertions, fn
          {type, _} -> type
          {type, _, _} -> type
        end)

      assert :escalated in assertion_types
    end

    test "adds constraint assertions for prohibitions" do
      cases = DSL.from_spec(@sample_spec)

      # All cases should have constraint_respected assertions for prohibition constraints
      for test_case <- cases do
        constraint_assertions =
          Enum.filter(test_case.assertions, fn
            {:constraint_respected, _} -> true
            _ -> false
          end)

        assert length(constraint_assertions) > 0
      end
    end

    test "handles empty spec gracefully" do
      assert DSL.from_spec(%{}) == []
    end
  end
end
