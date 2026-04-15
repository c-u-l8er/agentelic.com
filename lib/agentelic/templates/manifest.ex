defmodule Agentelic.Templates.Manifest do
  @moduledoc """
  Template manifest schema and validation.

  A template manifest (template.json) describes a code generation template:
  name, version, framework, product_type, dependencies, and hash.
  """

  @required_fields ~w(name version framework product_type)
  @valid_frameworks ~w(elixir typescript python)
  @valid_product_types ~w(mcp_server agent library website cli)

  @type t :: %{
          name: String.t(),
          version: String.t(),
          framework: String.t(),
          product_type: String.t(),
          min_spec_version: String.t() | nil,
          dependencies: map(),
          hash: String.t() | nil
        }

  @doc """
  Validate a template manifest map.

  Returns `:ok` or `{:error, reasons}`.
  """
  @spec validate(map()) :: :ok | {:error, [String.t()]}
  def validate(manifest) when is_map(manifest) do
    errors =
      []
      |> check_required(manifest)
      |> check_framework(manifest)
      |> check_product_type(manifest)
      |> check_version_format(manifest)

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp check_required(errors, manifest) do
    missing =
      @required_fields
      |> Enum.reject(&Map.has_key?(manifest, &1))

    case missing do
      [] -> errors
      fields -> ["Missing required fields: #{Enum.join(fields, ", ")}" | errors]
    end
  end

  defp check_framework(errors, manifest) do
    case Map.get(manifest, "framework") do
      nil ->
        errors

      fw when fw in @valid_frameworks ->
        errors

      fw ->
        [
          "Invalid framework: #{fw}. Must be one of: #{Enum.join(@valid_frameworks, ", ")}"
          | errors
        ]
    end
  end

  defp check_product_type(errors, manifest) do
    case Map.get(manifest, "product_type") do
      nil -> errors
      pt when pt in @valid_product_types -> errors
      pt -> ["Invalid product_type: #{pt}" | errors]
    end
  end

  defp check_version_format(errors, manifest) do
    case Map.get(manifest, "version") do
      nil ->
        errors

      version ->
        if Regex.match?(~r/^\d+\.\d+\.\d+/, version) do
          errors
        else
          ["Invalid version format: #{version}. Must be semver (e.g., 1.0.0)" | errors]
        end
    end
  end
end
