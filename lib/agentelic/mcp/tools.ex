defmodule Agentelic.MCP.Tools do
  @moduledoc """
  MCP tool definitions and handlers.

  9 tools: agent_create, agent_build, agent_test, agent_deploy, agent_status,
  template_list, template_pin, spec_validate, test_explain
  """

  alias Agentelic.Repo
  alias Agentelic.Agents.Agent
  alias Agentelic.Builds.Build
  alias Agentelic.Testing.TestRun
  alias Agentelic.Deploy.Deployment
  alias Agentelic.Pipeline.{Parser, Orchestrator}
  alias Agentelic.Templates.Registry

  import Ecto.Query

  @uuid_re ~r/\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/

  @doc "Return all tool definitions for tools/list."
  @spec definitions() :: [map()]
  def definitions do
    [
      %{
        "name" => "agent_create",
        "description" => "Create a new agent from a SPEC.md and ampersand.json",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "name" => %{"type" => "string", "description" => "Agent name"},
            "spec_path" => %{"type" => "string", "description" => "Path to SPEC.md"},
            "ampersand_path" => %{"type" => "string", "description" => "Path to ampersand.json"},
            "framework" => %{"type" => "string", "enum" => ["elixir", "typescript", "python"]},
            "product_type" => %{
              "type" => "string",
              "enum" => ["mcp_server", "agent", "library", "website", "cli"]
            },
            "workspace_id" => %{"type" => "string"},
            "user_id" => %{"type" => "string"}
          },
          "required" => ["name", "spec_path", "framework", "workspace_id", "user_id"]
        }
      },
      %{
        "name" => "agent_ensure",
        "description" =>
          "Find-or-create an agent by slug within a workspace. Returns agent_id. Safe to call repeatedly — idempotent per (workspace_id, slug).",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "name" => %{"type" => "string", "description" => "Human-readable name"},
            "slug" => %{
              "type" => "string",
              "description" =>
                "Slug (derived from name when omitted). Lookup key within a workspace."
            },
            "framework" => %{"type" => "string", "enum" => ["elixir", "typescript", "python"]},
            "product_type" => %{
              "type" => "string",
              "enum" => ["mcp_server", "agent", "library", "website", "cli"]
            },
            "spec_path" => %{"type" => "string"},
            "workspace_id" => %{"type" => "string"},
            "user_id" => %{"type" => "string"}
          },
          "required" => ["workspace_id", "user_id"]
        }
      },
      %{
        "name" => "agent_build",
        "description" => "Run 4-stage build pipeline for an agent",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "agent_id" => %{"type" => "string"},
            "spec_content" => %{
              "type" => "string",
              "description" =>
                "Optional inline spec. Use when the build server cannot read agent.spec_path from its local filesystem."
            }
          },
          "required" => ["agent_id"]
        }
      },
      %{
        "name" => "agent_test",
        "description" => "Execute deterministic tests for a build",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "agent_id" => %{"type" => "string"},
            "build_id" => %{"type" => "string"}
          },
          "required" => ["agent_id", "build_id"]
        }
      },
      %{
        "name" => "agent_deploy",
        "description" => "Deploy a build to staging/canary/production with governance",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "agent_id" => %{"type" => "string"},
            "build_id" => %{"type" => "string"},
            "environment" => %{"type" => "string", "enum" => ["staging", "canary", "production"]},
            "autonomy_level" => %{"type" => "string", "enum" => ["observe", "advise", "act"]},
            "approved_by" => %{"type" => "string"}
          },
          "required" => ["agent_id", "build_id", "environment"]
        }
      },
      %{
        "name" => "agent_status",
        "description" => "Full agent status summary with latest build, test, and deployments",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "agent_id" => %{"type" => "string"}
          },
          "required" => ["agent_id"]
        }
      },
      %{
        "name" => "template_list",
        "description" => "List compatible templates for a framework + product type",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "framework" => %{"type" => "string"},
            "product_type" => %{"type" => "string"}
          }
        }
      },
      %{
        "name" => "template_pin",
        "description" => "Pin an agent to a specific template version",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "agent_id" => %{"type" => "string"},
            "template_version" => %{"type" => "string"}
          },
          "required" => ["agent_id", "template_version"]
        }
      },
      %{
        "name" => "spec_validate",
        "description" => "Validate a SPEC.md against SpecPrompt grammar",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "spec_path" => %{"type" => "string"},
            "spec_content" => %{"type" => "string"}
          }
        }
      },
      %{
        "name" => "test_explain",
        "description" => "Explain why a specific test passed/failed with full tool call trace",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "test_run_id" => %{"type" => "string"},
            "test_index" => %{"type" => "integer"}
          },
          "required" => ["test_run_id", "test_index"]
        }
      }
    ]
  end

  @doc "Dispatch a tool call to its handler."
  @spec call(String.t(), map()) :: {:ok, map()} | {:error, integer(), String.t()}
  def call("agent_create", args) do
    slug =
      args
      |> Map.get("slug")
      |> case do
        nil -> Map.get(args, "name", "")
        "" -> Map.get(args, "name", "")
        s -> s
      end
      |> slugify()

    changeset =
      Agent.changeset(%Agent{}, %{
        name: Map.get(args, "name"),
        slug: slug,
        spec_path: Map.get(args, "spec_path"),
        ampersand_path: Map.get(args, "ampersand_path"),
        framework: Map.get(args, "framework"),
        product_type: safe_atom(Map.get(args, "product_type", "agent")),
        workspace_id: Map.get(args, "workspace_id"),
        user_id: Map.get(args, "user_id")
      })

    case Repo.insert(changeset) do
      {:ok, agent} ->
        {:ok,
         %{"agent_id" => agent.id, "status" => to_string(agent.status), "slug" => agent.slug}}

      {:error, changeset} ->
        errors = format_changeset_errors(changeset)
        {:error, -32602, "Validation failed: #{errors}"}
    end
  end

  def call("agent_ensure", args) do
    workspace_id = Map.get(args, "workspace_id")
    user_id = Map.get(args, "user_id")

    name = Map.get(args, "name") || Map.get(args, "slug") || "agent"
    slug = args |> Map.get("slug", name) |> slugify()

    cond do
      workspace_id in [nil, ""] ->
        {:error, -32602, "workspace_id is required"}

      user_id in [nil, ""] ->
        {:error, -32602, "user_id is required"}

      true ->
        existing =
          if is_binary(workspace_id) and Regex.match?(@uuid_re, workspace_id) do
            Repo.one(from a in Agent, where: a.workspace_id == ^workspace_id and a.slug == ^slug)
          else
            nil
          end

        case existing do
          %Agent{} = agent ->
            {:ok,
             %{
               "agent_id" => agent.id,
               "slug" => agent.slug,
               "status" => to_string(agent.status),
               "created" => false
             }}

          nil ->
            changeset =
              Agent.changeset(%Agent{}, %{
                name: name,
                slug: slug,
                spec_path: Map.get(args, "spec_path", "inline"),
                framework: Map.get(args, "framework", "elixir"),
                product_type: safe_atom(Map.get(args, "product_type", "agent")),
                workspace_id: workspace_id,
                user_id: user_id
              })

            case Repo.insert(changeset) do
              {:ok, agent} ->
                {:ok,
                 %{
                   "agent_id" => agent.id,
                   "slug" => agent.slug,
                   "status" => to_string(agent.status),
                   "created" => true
                 }}

              {:error, changeset} ->
                {:error, -32602, "Ensure failed: #{format_changeset_errors(changeset)}"}
            end
        end
    end
  end

  def call("agent_build", %{"agent_id" => agent_id} = args) do
    case safe_get(Agent, agent_id) do
      nil ->
        {:error, -32602, "Agent not found: #{agent_id}"}

      agent ->
        # Prefer inline spec_content when provided (remote callers can't read
        # the server's filesystem); fall back to agent.spec_path otherwise.
        spec_read_result =
          case Map.get(args, "spec_content") do
            content when is_binary(content) and content != "" -> {:ok, content}
            _ -> File.read(agent.spec_path || "")
          end

        case spec_read_result do
          {:ok, spec_content} ->
            # Create build record
            build_attrs = %{
              agent_id: agent.id,
              workspace_id: agent.workspace_id,
              version: next_version(agent),
              spec_hash: Parser.compute_hash(spec_content)
            }

            case Repo.insert(Build.changeset(%Build{}, build_attrs)) do
              {:ok, build} ->
                # Run pipeline asynchronously. Wrap in try/rescue so a stage
                # crash (e.g. missing `mix` binary) marks the build failed
                # rather than leaving it stuck in an intermediate status.
                Task.start(fn ->
                  try do
                    Orchestrator.run(build,
                      spec_content: spec_content,
                      framework: agent.framework,
                      product_type: agent.product_type,
                      template_pin: agent.template_pin
                    )
                  rescue
                    e ->
                      require Logger

                      Logger.error(
                        "Pipeline crashed for build #{build.id}: #{Exception.format(:error, e, __STACKTRACE__)}"
                      )

                      Repo.get(Build, build.id)
                      |> case do
                        nil ->
                          :ok

                        current ->
                          current
                          |> Build.stage_changeset(%{
                            status: :failed,
                            error_message: "Pipeline crashed: #{Exception.message(e)}"
                          })
                          |> Repo.update()
                      end
                  end
                end)

                {:ok, %{"build_id" => build.id, "status" => "pending"}}

              {:error, changeset} ->
                {:error, -32602, "Build creation failed: #{format_changeset_errors(changeset)}"}
            end

          {:error, reason} ->
            {:error, -32602, "Cannot read spec at #{agent.spec_path}: #{inspect(reason)}"}
        end
    end
  end

  def call("agent_test", %{"agent_id" => agent_id, "build_id" => build_id}) do
    with %Agent{} = agent <- safe_get(Agent, agent_id),
         %Build{status: :succeeded} = build <- safe_get(Build, build_id) do
      # Load spec to generate/load test cases
      spec_content = if agent.spec_path, do: File.read(agent.spec_path), else: {:error, :nospec}

      case spec_content do
        {:ok, content} ->
          {:ok, spec} = Parser.parse(content)

          # Load compiled tests if available, else generate from spec
          {test_cases, tests_hash} =
            case Agentelic.Pipeline.TestIntake.load(spec, []) do
              {:ok, cases, hash} -> {cases, hash}
              {:error, _} -> {Agentelic.Testing.DSL.from_spec(spec), Parser.compute_hash(content)}
            end

          # Execute tests
          {:ok, test_result} = Agentelic.Testing.Runner.execute(build, test_cases)

          # Persist TestRun
          test_run_attrs = %{
            agent_id: agent.id,
            build_id: build.id,
            workspace_id: agent.workspace_id,
            test_suite: "spec_acceptance",
            compiled_tests_hash: tests_hash,
            status: test_result.status,
            total_tests: test_result.total_tests,
            passed_tests: test_result.passed_tests,
            failed_tests: test_result.failed_tests,
            error_tests: test_result.error_tests,
            duration_ms: test_result.duration_ms
          }

          case Repo.insert(TestRun.changeset(%TestRun{}, test_run_attrs)) do
            {:ok, run} ->
              {:ok,
               %{
                 "test_run_id" => run.id,
                 "status" => to_string(run.status),
                 "total" => run.total_tests,
                 "passed" => run.passed_tests,
                 "failed" => run.failed_tests
               }}

            {:error, changeset} ->
              {:error, -32602, "TestRun creation failed: #{format_changeset_errors(changeset)}"}
          end

        {:error, reason} ->
          {:error, -32602, "Cannot read spec at #{agent.spec_path}: #{inspect(reason)}"}
      end
    else
      nil -> {:error, -32602, "Agent or build not found"}
      %Build{status: status} -> {:error, -32602, "Build status must be succeeded, got: #{status}"}
    end
  end

  def call("agent_deploy", args) do
    agent_id = Map.get(args, "agent_id")

    case safe_get(Agent, agent_id) do
      nil ->
        {:error, -32602, "Agent not found: #{agent_id}"}

      agent ->
        changeset =
          Deployment.changeset(%Deployment{}, %{
            agent_id: agent.id,
            build_id: Map.get(args, "build_id"),
            workspace_id: agent.workspace_id,
            environment: safe_atom(Map.get(args, "environment", "staging")),
            autonomy_level: safe_atom(Map.get(args, "autonomy_level", "observe")),
            approved_by: Map.get(args, "approved_by")
          })

        case Repo.insert(changeset) do
          {:ok, deployment} ->
            {:ok, %{"deployment_id" => deployment.id, "status" => to_string(deployment.status)}}

          {:error, changeset} ->
            {:error, -32602, "Deploy failed: #{format_changeset_errors(changeset)}"}
        end
    end
  end

  def call("agent_status", %{"agent_id" => agent_id}) do
    case safe_get(Agent, agent_id) do
      nil ->
        {:error, -32602, "Agent not found: #{agent_id}"}

      agent ->
        agent = Repo.preload(agent, [:builds, :test_runs, :deployments])

        # NOTE: `:desc` alone does structural comparison on DateTime, which produces
        # the WRONG order (oldest first). Must use `{:desc, DateTime}` so the
        # comparator uses DateTime.compare/2.
        latest_build = agent.builds |> Enum.sort_by(& &1.created_at, {:desc, DateTime}) |> List.first()
        latest_test = agent.test_runs |> Enum.sort_by(& &1.created_at, {:desc, DateTime}) |> List.first()

        {:ok,
         %{
           "agent" => %{
             "id" => agent.id,
             "name" => agent.name,
             "slug" => agent.slug,
             "status" => to_string(agent.status),
             "framework" => agent.framework,
             "product_type" => to_string(agent.product_type),
             "spec_hash" => agent.spec_hash
           },
           "latest_build" => build_summary(latest_build),
           "latest_test" => test_summary(latest_test),
           "deployments" =>
             agent.deployments
             |> Enum.map(fn d ->
               %{
                 "id" => d.id,
                 "environment" => to_string(d.environment),
                 "status" => to_string(d.status)
               }
             end)
         }}
    end
  end

  def call("template_list", args) do
    templates =
      Registry.list(
        framework: Map.get(args, "framework"),
        product_type: safe_atom(Map.get(args, "product_type"))
      )

    {:ok,
     %{
       "templates" =>
         Enum.map(templates, fn t ->
           %{"name" => t.name, "version" => t.version, "hash" => t.hash}
         end)
     }}
  end

  def call("template_pin", %{"agent_id" => agent_id, "template_version" => version}) do
    case safe_get(Agent, agent_id) do
      nil ->
        {:error, -32602, "Agent not found"}

      agent ->
        changeset = Ecto.Changeset.change(agent, template_pin: version)

        case Repo.update(changeset) do
          {:ok, agent} -> {:ok, %{"updated_at" => to_string(agent.updated_at)}}
          {:error, _} -> {:error, -32602, "Failed to pin template"}
        end
    end
  end

  def call("spec_validate", args) do
    content =
      case Map.get(args, "spec_content") do
        nil ->
          case Map.get(args, "spec_path") do
            nil -> {:error, "spec_path or spec_content required"}
            path -> File.read(path)
          end

        content ->
          {:ok, content}
      end

    case content do
      {:ok, spec_content} ->
        case Parser.parse(spec_content) do
          {:ok, spec} ->
            {:ok,
             %{"valid" => true, "spec_hash" => spec.spec_hash, "errors" => [], "warnings" => []}}

          {:error, reason} ->
            {:ok, %{"valid" => false, "errors" => [reason], "warnings" => []}}
        end

      {:error, reason} ->
        {:error, -32602, "Cannot read spec: #{inspect(reason)}"}
    end
  end

  def call("test_explain", %{"test_run_id" => test_run_id, "test_index" => index}) do
    case safe_get(TestRun, test_run_id) do
      nil ->
        {:error, -32602, "Test run not found: #{test_run_id}"}

      test_run ->
        case Enum.at(test_run.results, index) do
          nil ->
            {:error, -32602,
             "Test index #{index} out of range (#{length(test_run.results)} tests)"}

          result ->
            {:ok,
             %{
               "test_name" => result.test_name,
               "status" => to_string(result.status),
               "given" => result.given,
               "expected" => result.expected,
               "actual" => result.actual,
               "tool_calls" => result.tool_calls,
               "assertions" => result.assertions,
               "error_message" => result.error_message,
               "duration_ms" => result.duration_ms
             }}
        end
    end
  end

  def call(tool_name, _args) do
    {:error, -32601, "Unknown tool: #{tool_name}"}
  end

  # --- Helpers ---

  defp next_version(agent) do
    case Repo.one(
           from b in Build,
             where: b.agent_id == ^agent.id,
             order_by: [desc: b.created_at],
             limit: 1,
             select: b.version
         ) do
      nil ->
        "0.1.0"

      version ->
        case Version.parse(version) do
          {:ok, v} -> "#{v.major}.#{v.minor}.#{v.patch + 1}"
          _ -> "0.1.0"
        end
    end
  end

  defp build_summary(nil), do: nil

  defp build_summary(build) do
    %{
      "id" => build.id,
      "version" => build.version,
      "status" => to_string(build.status),
      "artifact_hash" => build.artifact_hash,
      "spec_hash" => build.spec_hash
    }
  end

  defp test_summary(nil), do: nil

  defp test_summary(test_run) do
    %{
      "id" => test_run.id,
      "status" => to_string(test_run.status),
      "total" => test_run.total_tests,
      "passed" => test_run.passed_tests,
      "failed" => test_run.failed_tests
    }
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map(fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
    |> Enum.join("; ")
  end

  defp slugify(str) when is_binary(str) do
    str
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp slugify(_), do: ""

  defp safe_atom(nil), do: nil
  defp safe_atom(str) when is_atom(str), do: str

  defp safe_atom(str) when is_binary(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> String.to_atom(str)
  end

  # Look up a record by UUID string, returning nil (not raising) on
  # malformed / non-UUID input so that MCP callers can treat it as "not found"
  # instead of an HTTP 400 cast crash.
  defp safe_get(_schema, id) when not is_binary(id), do: nil

  defp safe_get(schema, id) do
    if Regex.match?(@uuid_re, id) do
      Repo.get(schema, id)
    else
      nil
    end
  end
end
