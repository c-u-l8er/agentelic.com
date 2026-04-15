defmodule Agentelic.Templates.Registry do
  @moduledoc """
  Template version management.

  Lists templates by {framework, product_type}.
  Version pinning: agent-level > workspace-level > global default.
  Template immutability: once published, a template version never changes.
  """

  @templates_dir "priv/templates"

  @type template :: %{
          name: String.t(),
          version: String.t(),
          hash: String.t(),
          framework: String.t(),
          product_type: atom(),
          path: String.t(),
          manifest: map()
        }

  @doc """
  List all available templates, optionally filtered by framework and product_type.
  """
  @spec list(keyword()) :: [template()]
  def list(opts \\ []) do
    framework = Keyword.get(opts, :framework)
    product_type = Keyword.get(opts, :product_type)

    load_all_templates()
    |> filter_by(:framework, framework)
    |> filter_by(:product_type, product_type)
  end

  @doc """
  Resolve the correct template for a build.

  Pinning hierarchy: agent-level > workspace-level > global default.
  """
  @spec resolve(String.t(), atom(), keyword()) :: {:ok, template()} | {:error, String.t()}
  def resolve(framework, product_type, opts \\ []) do
    template_pin = Keyword.get(opts, :template_pin)
    workspace_pin = Keyword.get(opts, :workspace_template_pin)

    version = template_pin || workspace_pin

    templates =
      list(framework: framework, product_type: product_type)

    case {version, templates} do
      {nil, [latest | _]} ->
        {:ok, latest}

      {nil, []} ->
        {:error, "No template found for #{framework}/#{product_type}"}

      {pin, _} ->
        case Enum.find(templates, &(&1.version == pin)) do
          nil -> {:error, "Template version #{pin} not found for #{framework}/#{product_type}"}
          template -> {:ok, template}
        end
    end
  end

  # --- Internal ---

  defp load_all_templates do
    templates_path = Application.app_dir(:agentelic, @templates_dir)

    if File.dir?(templates_path) do
      templates_path
      |> scan_templates()
    else
      # Fallback to priv/templates relative to project root
      "priv/templates"
      |> scan_templates()
    end
  end

  defp scan_templates(base_path) do
    Path.wildcard(Path.join([base_path, "**", "template.json"]))
    |> Enum.map(&load_template/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.version, :desc)
  end

  defp load_template(manifest_path) do
    case File.read(manifest_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, manifest} ->
            %{
              name: Map.get(manifest, "name", "unknown"),
              version: Map.get(manifest, "version", "0.0.0"),
              hash: compute_template_hash(manifest_path),
              framework: Map.get(manifest, "framework", "unknown"),
              product_type: safe_atom(Map.get(manifest, "product_type", "agent")),
              path: Path.dirname(manifest_path),
              manifest: manifest
            }

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp compute_template_hash(manifest_path) do
    dir = Path.dirname(manifest_path)

    Path.wildcard(Path.join(dir, "**/*"))
    |> Enum.filter(&File.regular?/1)
    |> Enum.sort()
    |> Enum.map(&File.read!/1)
    |> Enum.join()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp filter_by(templates, _field, nil), do: templates

  defp filter_by(templates, field, value) do
    Enum.filter(templates, &(Map.get(&1, field) == value))
  end

  defp safe_atom(str) when is_binary(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> String.to_atom(str)
  end

  defp safe_atom(other), do: other
end
