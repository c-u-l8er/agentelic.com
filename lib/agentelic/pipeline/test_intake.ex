defmodule Agentelic.Pipeline.TestIntake do
  @moduledoc """
  Stage 1.5: TEST INTAKE — compiled test loading from SpecPrompt.

  Bridges SpecPrompt compiled tests into Agentelic's Test DSL format.
  Only approved tests (approved == true) are used.
  Compiled tests are cached by {spec_hash, test_index}.
  """

  alias Agentelic.Testing.DSL
  alias Agentelic.Pipeline.Parser

  @doc """
  Load compiled tests for a spec.

  Tries compiled tests from opts first, falls back to generating from spec.
  Returns `{:ok, test_cases, compiled_tests_hash}`.
  """
  @spec load(map(), keyword()) :: {:ok, [DSL.test_case()], String.t()} | {:error, String.t()}
  def load(spec, opts \\ []) do
    compiled_tests_json = Keyword.get(opts, :compiled_tests)

    cond do
      compiled_tests_json != nil ->
        load_compiled(compiled_tests_json, spec)

      true ->
        # Fall back to generating from spec acceptance tests
        generate_from_spec(spec)
    end
  end

  @doc """
  Load pre-compiled tests from JSON.

  Only approved tests (approved == true) are included.
  """
  def load_compiled(json, spec) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, tests} when is_list(tests) ->
        load_compiled(tests, spec)

      {:error, reason} ->
        {:error, "Invalid compiled tests JSON: #{inspect(reason)}"}
    end
  end

  def load_compiled(tests, _spec) when is_list(tests) do
    approved =
      tests
      |> Enum.filter(fn test -> Map.get(test, "approved", false) == true end)

    test_cases =
      approved
      |> Enum.map(&compiled_test_to_dsl/1)

    hash = compute_tests_hash(approved)

    {:ok, test_cases, hash}
  end

  defp generate_from_spec(spec) do
    test_cases = DSL.from_spec(spec)
    hash = compute_tests_hash(test_cases)
    {:ok, test_cases, hash}
  end

  defp compiled_test_to_dsl(compiled) do
    %{
      name: Map.get(compiled, "name", "unnamed"),
      given: Map.get(compiled, "given", ""),
      expected: Map.get(compiled, "expected", ""),
      mocks:
        compiled
        |> Map.get("mocks", [])
        |> Enum.map(fn mock ->
          %{
            tool_name: Map.get(mock, "tool_name", ""),
            match_args: Map.get(mock, "match_args", %{}),
            return: Map.get(mock, "return", nil)
          }
        end),
      assertions:
        compiled
        |> Map.get("assertions", [])
        |> Enum.map(&parse_assertion/1),
      timeout_ms: Map.get(compiled, "timeout_ms", 30_000)
    }
  end

  defp parse_assertion(%{"type" => "contains", "value" => value}),
    do: {:contains, value}

  defp parse_assertion(%{"type" => "not_contains", "value" => value}),
    do: {:not_contains, value}

  defp parse_assertion(%{"type" => "tool_called", "tool" => tool, "args" => args}),
    do: {:tool_called, tool, args}

  defp parse_assertion(%{"type" => "tool_not_called", "tool" => tool}),
    do: {:tool_not_called, tool}

  defp parse_assertion(%{"type" => "escalated", "value" => value}),
    do: {:escalated, value}

  defp parse_assertion(%{"type" => "constraint_respected", "constraint" => c}),
    do: {:constraint_respected, c}

  defp parse_assertion(other),
    do: {:unknown, other}

  defp compute_tests_hash(tests) do
    tests
    |> :erlang.term_to_binary()
    |> Parser.compute_hash()
  end
end
