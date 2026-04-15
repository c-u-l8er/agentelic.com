defmodule Agentelic.Testing.DSL do
  @moduledoc """
  Deterministic testing DSL for agents built from SpecPrompt specs.

  Tests are generated from acceptance criteria, not hand-written.
  See spec section 4.7.
  """

  @type assertion ::
          {:contains, String.t()}
          | {:not_contains, String.t()}
          | {:tool_called, String.t(), map()}
          | {:tool_not_called, String.t()}
          | {:escalated, boolean()}
          | {:escalation_reason, Regex.t()}
          | {:constraint_respected, String.t()}
          | {:response_time_ms, :lt, integer()}

  @type mock_spec :: %{
          tool_name: String.t(),
          match_args: map(),
          return: term()
        }

  @type test_case :: %{
          name: String.t(),
          given: String.t(),
          expected: String.t(),
          mocks: [mock_spec()],
          assertions: [assertion()],
          timeout_ms: integer()
        }

  @doc """
  Generate test cases from a parsed SpecPrompt spec's acceptance tests.
  """
  @spec from_spec(map()) :: [test_case()]
  def from_spec(%{acceptance_tests: tests, capabilities: capabilities, constraints: constraints}) do
    for test <- tests do
      %{
        name: Map.get(test, :given, "unnamed test"),
        given: Map.get(test, :given, ""),
        expected: Map.get(test, :expected, ""),
        mocks: infer_mocks(test, capabilities),
        assertions: infer_assertions(test, constraints),
        timeout_ms: 30_000
      }
    end
  end

  def from_spec(%{acceptance_tests: tests}) do
    from_spec(%{acceptance_tests: tests, capabilities: [], constraints: []})
  end

  def from_spec(_), do: []

  @doc """
  Infer mock specifications from a test case and available capabilities.
  """
  @spec infer_mocks(map(), [map()]) :: [mock_spec()]
  def infer_mocks(test, capabilities) do
    given = Map.get(test, :given, "")

    capabilities
    |> Enum.filter(fn cap ->
      cap_name = Map.get(cap, :name, "")

      # Match on full name or on the resource part before the colon
      # e.g. "orders:read" matches if "order" appears in the given text
      cap_tokens =
        cap_name
        |> String.downcase()
        |> String.split(~r/[:_\-\s]+/)
        |> Enum.reject(&(&1 == ""))

      given_lower = String.downcase(given)

      String.contains?(given_lower, String.downcase(cap_name)) or
        Enum.any?(cap_tokens, fn token ->
          # Match singular/plural forms (e.g. "order" matches "orders" and vice versa)
          String.contains?(given_lower, token) or
            String.contains?(given_lower, String.trim_trailing(token, "s"))
        end)
    end)
    |> Enum.map(fn cap ->
      %{
        tool_name: Map.get(cap, :name, ""),
        match_args: %{},
        return: %{status: "ok"}
      }
    end)
  end

  @doc """
  Infer assertions from a test case and constraints.
  """
  @spec infer_assertions(map(), [map()]) :: [assertion()]
  def infer_assertions(test, constraints) do
    expected = Map.get(test, :expected, "")

    # Build assertions from the expected text
    contains_assertions =
      if expected != "" do
        [{:contains, expected}]
      else
        []
      end

    # Check for escalation patterns
    escalation_assertions =
      if String.contains?(String.downcase(expected), "escalat") do
        [{:escalated, true}]
      else
        []
      end

    # Add constraint assertions for prohibition-type constraints
    constraint_assertions =
      constraints
      |> Enum.filter(fn c -> Map.get(c, :type) == :prohibition end)
      |> Enum.map(fn c -> {:constraint_respected, Map.get(c, :description, "")} end)

    contains_assertions ++ escalation_assertions ++ constraint_assertions
  end
end
