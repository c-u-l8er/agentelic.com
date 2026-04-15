defmodule Agentelic.Testing.CompiledIntake do
  @moduledoc """
  SpecPrompt compiled test bridge.

  Loads SpecPrompt.CompiledTest[] from JSON and converts to Agentelic Test DSL format.
  Only approved tests (approved == true) are used.
  Generates compilation prompts for LLM-assisted test compilation when needed.
  """

  @doc """
  Generate a compilation prompt for a test that hasn't been compiled yet.

  Returns a prompt string that can be given to an LLM to produce compiled test JSON.
  Agentelic does NOT make LLM calls itself — it generates the prompt for the agent/user.
  """
  @spec compilation_prompt(map(), map()) :: String.t()
  def compilation_prompt(acceptance_test, spec) do
    """
    You are compiling an acceptance test into a deterministic test case for Agentelic.

    ## Agent Spec
    Name: #{Map.get(spec, :name, "unknown")}
    Version: #{Map.get(spec, :version, "0.0.0")}

    ## Acceptance Test
    Given: #{Map.get(acceptance_test, :given, "")}
    Expected: #{Map.get(acceptance_test, :expected, "")}

    ## Available Capabilities
    #{format_capabilities(Map.get(spec, :capabilities, []))}

    ## Constraints
    #{format_constraints(Map.get(spec, :constraints, []))}

    ## Output Format
    Return a JSON object with this structure:
    ```json
    {
      "name": "descriptive test name",
      "given": "the test precondition",
      "expected": "the expected outcome",
      "approved": false,
      "mocks": [
        {"tool_name": "tool:action", "match_args": {}, "return": {}}
      ],
      "assertions": [
        {"type": "contains|not_contains|tool_called|tool_not_called|escalated|constraint_respected", "value": "..."}
      ],
      "timeout_ms": 30000
    }
    ```

    Important:
    - Set "approved" to false — a human must approve before use
    - Infer which tools need to be mocked from the test scenario
    - Include negative assertions for any constraints that apply
    """
  end

  defp format_capabilities(capabilities) do
    capabilities
    |> Enum.map(fn cap -> "- #{Map.get(cap, :name, "")}: #{Map.get(cap, :description, "")}" end)
    |> Enum.join("\n")
  end

  defp format_constraints(constraints) do
    constraints
    |> Enum.map(fn c -> "- [#{Map.get(c, :type, :general)}] #{Map.get(c, :description, "")}" end)
    |> Enum.join("\n")
  end
end
