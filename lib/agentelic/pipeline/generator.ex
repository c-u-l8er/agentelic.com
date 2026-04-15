defmodule Agentelic.Pipeline.Generator do
  @moduledoc """
  Stage 2: GENERATE — template-based code generation.

  Takes a parsed SpecPrompt.Spec + template and produces generated source files.
  Deterministic: same spec + same template version = same output.
  """

  alias Agentelic.Templates.{Registry, Renderer}

  @type generated_file :: %{
          path: String.t(),
          content: String.t()
        }

  @type template_info :: %{
          name: String.t(),
          version: String.t(),
          hash: String.t()
        }

  @doc """
  Generate source files from a parsed spec using a pinned template.

  Options:
    - `:framework` - target framework (required)
    - `:product_type` - product type (required)
    - `:template_version` - pinned template version (optional, uses default if not set)
    - `:template_pin` - agent-level template pin (optional)

  Returns `{:ok, [generated_file], template_info}` or `{:error, reason}`.
  """
  @spec generate(map(), keyword()) ::
          {:ok, [generated_file()], template_info()} | {:error, String.t()}
  def generate(spec, opts \\ []) do
    framework = Keyword.get(opts, :framework, "elixir")
    product_type = Keyword.get(opts, :product_type, :mcp_server)

    with {:ok, template} <- Registry.resolve(framework, product_type, opts),
         {:ok, files} <- Renderer.render(template, spec, opts) do
      template_info = %{
        name: template.name,
        version: template.version,
        hash: template.hash
      }

      {:ok, files, template_info}
    end
  end
end
