defmodule Agentelic.Pipeline.Tester do
  @moduledoc """
  Stage 4: TEST — run deterministic tests against a compiled artifact.

  For each test case:
    1. Set up mocked tool state from Given/When precondition
    2. Send precondition text as agent input
    3. Capture agent output + tool calls
    4. Validate output against Expected assertions
  """

  alias Agentelic.Testing.Runner

  @doc """
  Run compiled test cases against a build artifact.

  Returns `{:ok, test_run}` or `{:error, reason}`.
  """
  @spec run(map(), [map()], keyword()) :: {:ok, map()} | {:error, String.t()}
  def run(artifact, test_cases, opts \\ []) do
    Runner.execute(artifact, test_cases, opts)
  end
end
