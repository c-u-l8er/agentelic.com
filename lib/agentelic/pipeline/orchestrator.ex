defmodule Agentelic.Pipeline.Orchestrator do
  @moduledoc """
  4-stage build pipeline orchestrator.

  Stages:
    1. PARSE — SpecPrompt.Spec parsing
    1.5. TEST INTAKE — compiled test loading
    2. GENERATE — template-based code generation
    3. COMPILE — build artifact compilation
    4. TEST — run deterministic tests

  Determinism: same {spec_hash, template_hash} → same artifact_hash.
  """

  alias Agentelic.Builds.Build
  alias Agentelic.Pipeline.{Parser, TestIntake, Generator, Compiler, Tester}
  alias Agentelic.Publisher
  alias Agentelic.Repo

  require Logger

  @type pipeline_result ::
          {:ok, Build.t()}
          | {:error, atom(), String.t(), Build.t()}

  @doc """
  Run the full build pipeline for an agent.

  Returns `{:ok, build}` on success or `{:error, stage, message, build}` on failure.
  """
  @spec run(Build.t(), keyword()) :: pipeline_result()
  def run(%Build{} = build, opts \\ []) do
    build
    |> stage_parse(opts)
    |> then_stage(:test_intake, &stage_test_intake(&1, opts))
    |> then_stage(:generate, &stage_generate(&1, opts))
    |> then_stage(:compile, &stage_compile(&1, opts))
    |> then_stage(:test, &stage_test(&1, opts))
    |> finalize()
  end

  # --- Stage 1: PARSE ---

  defp stage_parse(build, opts) do
    Logger.info("Pipeline PARSE starting for build #{build.id}")
    build = update_status!(build, :parsing)

    spec_content = Keyword.fetch!(opts, :spec_content)
    start = System.monotonic_time(:millisecond)

    case Parser.parse(spec_content) do
      {:ok, spec} ->
        duration = System.monotonic_time(:millisecond) - start

        build =
          update_stage!(build, %{
            parse_result: spec_to_storable(spec),
            parse_duration_ms: duration,
            spec_hash: spec.spec_hash
          })

        {:ok, build, spec}

      {:error, reason} ->
        duration = System.monotonic_time(:millisecond) - start
        build = fail_build!(build, "PARSE failed: #{reason}", %{parse_duration_ms: duration})
        {:error, :parse, reason, build}
    end
  end

  # --- Stage 1.5: TEST INTAKE ---

  defp stage_test_intake({:ok, build, spec}, opts) do
    Logger.info("Pipeline TEST_INTAKE starting for build #{build.id}")
    start = System.monotonic_time(:millisecond)

    case TestIntake.load(spec, opts) do
      {:ok, compiled_tests, tests_hash} ->
        _duration = System.monotonic_time(:millisecond) - start

        build =
          update_stage!(build, %{
            compiled_tests_hash: tests_hash
          })

        {:ok, build, spec, compiled_tests}

      {:error, reason} ->
        _duration = System.monotonic_time(:millisecond) - start
        build = fail_build!(build, "TEST_INTAKE failed: #{reason}")
        {:error, :test_intake, reason, build}
    end
  end

  # --- Stage 2: GENERATE ---

  defp stage_generate({:ok, build, spec, compiled_tests}, opts) do
    Logger.info("Pipeline GENERATE starting for build #{build.id}")
    build = update_status!(build, :generating)
    start = System.monotonic_time(:millisecond)

    case Generator.generate(spec, opts) do
      {:ok, generated_files, template_info} ->
        duration = System.monotonic_time(:millisecond) - start

        build =
          update_stage!(build, %{
            generation_result: %{files: Enum.map(generated_files, & &1.path)},
            generation_duration_ms: duration,
            template_version: template_info.version,
            template_hash: template_info.hash
          })

        {:ok, build, spec, compiled_tests, generated_files}

      {:error, reason} ->
        duration = System.monotonic_time(:millisecond) - start

        build =
          fail_build!(build, "GENERATE failed: #{reason}", %{generation_duration_ms: duration})

        {:error, :generate, reason, build}
    end
  end

  # --- Stage 3: COMPILE ---

  defp stage_compile({:ok, build, spec, compiled_tests, generated_files}, opts) do
    Logger.info("Pipeline COMPILE starting for build #{build.id}")
    build = update_status!(build, :compiling)
    start = System.monotonic_time(:millisecond)

    case Compiler.compile(generated_files, opts) do
      {:ok, artifact} ->
        duration = System.monotonic_time(:millisecond) - start

        build =
          update_stage!(build, %{
            compile_result: %{warnings: artifact.warnings},
            compile_duration_ms: duration,
            artifact_hash: artifact.hash,
            artifact_path: artifact.path
          })

        {:ok, build, spec, compiled_tests, artifact}

      {:error, reason} ->
        duration = System.monotonic_time(:millisecond) - start
        build = fail_build!(build, "COMPILE failed: #{reason}", %{compile_duration_ms: duration})
        {:error, :compile, reason, build}
    end
  end

  # --- Stage 4: TEST ---

  defp stage_test({:ok, build, _spec, compiled_tests, artifact}, opts) do
    Logger.info("Pipeline TEST starting for build #{build.id}")
    build = update_status!(build, :testing)
    start = System.monotonic_time(:millisecond)

    case Tester.run(artifact, compiled_tests, opts) do
      {:ok, test_run} ->
        duration = System.monotonic_time(:millisecond) - start

        build =
          update_stage!(build, %{
            test_result: %{
              total: test_run.total_tests,
              passed: test_run.passed_tests,
              failed: test_run.failed_tests
            },
            test_duration_ms: duration,
            status: :succeeded
          })

        {:ok, build}

      {:error, reason} ->
        duration = System.monotonic_time(:millisecond) - start
        build = fail_build!(build, "TEST failed: #{reason}", %{test_duration_ms: duration})
        {:error, :test, reason, build}
    end
  end

  # --- Helpers ---

  defp then_stage({:ok, _build, _spec} = result, _stage, fun), do: fun.(result)
  defp then_stage({:ok, _build, _spec, _tests} = result, _stage, fun), do: fun.(result)
  defp then_stage({:ok, _build, _spec, _tests, _files} = result, _stage, fun), do: fun.(result)
  defp then_stage({:ok, _build} = result, _stage, _fun), do: result
  defp then_stage({:error, _, _, _} = error, _stage, _fun), do: error

  defp finalize({:ok, build}) do
    # Emit ConsolidationEvent to FleetPrompt on success
    case Repo.get(Agentelic.Agents.Agent, build.agent_id) do
      nil ->
        Logger.warning("Agent #{build.agent_id} not found for ConsolidationEvent")

      agent ->
        Task.start(fn -> Publisher.publish_build_success(build, agent) end)
    end

    {:ok, build}
  end

  defp finalize({:error, stage, reason, build}), do: {:error, stage, reason, build}

  defp update_status!(build, status) do
    build
    |> Build.stage_changeset(%{status: status})
    |> Repo.update!()
  end

  defp update_stage!(build, attrs) do
    build
    |> Build.stage_changeset(attrs)
    |> Repo.update!()
  end

  defp fail_build!(build, message, extra_attrs \\ %{}) do
    attrs = Map.merge(extra_attrs, %{status: :failed, error_message: message})

    build
    |> Build.stage_changeset(attrs)
    |> Repo.update!()
  end

  defp spec_to_storable(spec) do
    spec
    |> Map.drop([:raw])
    |> Map.update(:capabilities, [], fn caps ->
      Enum.map(caps, fn
        %_{} = struct -> Map.from_struct(struct)
        map when is_map(map) -> map
      end)
    end)
  end
end
