defmodule Agentelic.Templates.Renderer do
  @moduledoc """
  EEx-based template expansion.

  Input: template + SpecPrompt.Spec + optional ampersand.json
  Output: generated source files
  """

  @doc """
  Render a template with spec data to produce source files.

  Returns `{:ok, [%{path: path, content: content}]}` or `{:error, reason}`.
  """
  @spec render(map(), map(), keyword()) :: {:ok, [map()]} | {:error, String.t()}
  def render(template, spec, opts \\ []) do
    template_path = template.path
    ampersand = Keyword.get(opts, :ampersand, %{})

    bindings = [
      spec: spec,
      agent_name: Map.get(spec, :name, "agent"),
      agent_module: module_name(Map.get(spec, :name, "agent")),
      version: Map.get(spec, :version, "0.0.0"),
      capabilities: Map.get(spec, :capabilities, []),
      constraints: Map.get(spec, :constraints, []),
      ampersand: ampersand,
      framework: template.framework
    ]

    try do
      files =
        template_path
        |> list_eex_files()
        |> Enum.map(fn eex_path ->
          output_path = eex_output_path(eex_path, template_path)
          content = EEx.eval_file(eex_path, bindings)
          %{path: output_path, content: content}
        end)

      {:ok, files}
    rescue
      e -> {:error, "Template rendering failed: #{Exception.message(e)}"}
    end
  end

  defp list_eex_files(template_path) do
    Path.wildcard(Path.join(template_path, "**/*.eex"))
  end

  defp eex_output_path(eex_path, template_path) do
    eex_path
    |> String.replace_prefix(template_path <> "/", "")
    |> String.replace_suffix(".eex", "")
  end

  defp module_name(name) do
    name
    |> String.split(~r/[-_\s]+/)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join()
  end
end
