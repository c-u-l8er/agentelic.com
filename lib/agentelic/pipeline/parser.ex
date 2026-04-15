defmodule Agentelic.Pipeline.Parser do
  @moduledoc """
  Stage 1: PARSE — SpecPrompt SPEC.md parsing.

  Consumes a SPEC.md file and produces a structured `SpecPrompt.Spec` map.
  Computes spec_hash (SHA-256) and validates required sections.
  """

  @required_sections [
    "Executive Summary",
    "Architecture",
    "Acceptance Tests"
  ]

  @type spec :: %{
          name: String.t(),
          version: String.t(),
          description: String.t(),
          capabilities: [map()],
          constraints: [map()],
          acceptance_tests: [map()],
          architecture: map(),
          sections: %{String.t() => String.t()},
          raw: String.t(),
          spec_hash: String.t()
        }

  @doc """
  Parse a SPEC.md file into a structured spec map.

  Returns `{:ok, spec}` or `{:error, reason}`.
  """
  @spec parse(String.t()) :: {:ok, spec()} | {:error, String.t()}
  def parse(spec_content) when is_binary(spec_content) do
    with {:ok, sections} <- extract_sections(spec_content),
         :ok <- validate_required_sections(sections),
         {:ok, frontmatter} <- parse_frontmatter(spec_content),
         capabilities <- parse_capabilities(sections),
         constraints <- parse_constraints(sections),
         acceptance_tests <- parse_acceptance_tests(sections) do
      spec = %{
        name: Map.get(frontmatter, :name, "unknown"),
        version: Map.get(frontmatter, :version, "0.0.0"),
        description: Map.get(frontmatter, :description, ""),
        capabilities: capabilities,
        constraints: constraints,
        acceptance_tests: acceptance_tests,
        architecture: parse_architecture(sections),
        sections: sections,
        raw: spec_content,
        spec_hash: compute_hash(spec_content)
      }

      {:ok, spec}
    end
  end

  @doc "Compute SHA-256 hash of content."
  @spec compute_hash(String.t()) :: String.t()
  def compute_hash(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end

  # --- Section extraction ---

  defp extract_sections(content) do
    sections =
      content
      |> String.split(~r/^##\s+/m)
      |> Enum.drop(1)
      |> Enum.map(fn section ->
        case String.split(section, "\n", parts: 2) do
          [title, body] -> {String.trim(title), String.trim(body)}
          [title] -> {String.trim(title), ""}
        end
      end)
      |> Map.new()

    {:ok, sections}
  end

  defp validate_required_sections(sections) do
    section_titles =
      sections
      |> Map.keys()
      |> Enum.map(&normalize_section_title/1)

    missing =
      @required_sections
      |> Enum.reject(fn required ->
        normalized = normalize_section_title(required)
        Enum.any?(section_titles, &String.contains?(&1, normalized))
      end)

    case missing do
      [] -> :ok
      missing -> {:error, "Missing required sections: #{Enum.join(missing, ", ")}"}
    end
  end

  defp normalize_section_title(title) do
    title
    |> String.downcase()
    |> String.replace(~r/^\d+\.\s*/, "")
    |> String.trim()
  end

  # --- Frontmatter parsing ---

  defp parse_frontmatter(content) do
    frontmatter =
      content
      |> String.split("\n")
      |> Enum.take_while(&(!String.starts_with?(&1, "---")))
      |> Enum.reduce(%{}, fn line, acc ->
        case Regex.run(~r/^\*\*(.+?):\*\*\s*(.+)/, line) do
          [_, key, value] ->
            atom_key =
              key
              |> String.downcase()
              |> String.replace(~r/\s+/, "_")
              |> String.to_atom()

            Map.put(acc, atom_key, String.trim(value))

          _ ->
            acc
        end
      end)

    # Also try to extract from first heading
    name =
      case Regex.run(~r/^#\s+(.+?)(?:\s*—|\s*-|\n)/, content) do
        [_, name] -> String.trim(name)
        _ -> Map.get(frontmatter, :name, "unknown")
      end

    {:ok, Map.put(frontmatter, :name, name)}
  end

  # --- Capability parsing ---

  defp parse_capabilities(sections) do
    sections
    |> find_section("capabilities")
    |> parse_list_items()
    |> Enum.map(fn item ->
      %{
        name: extract_capability_name(item),
        description: item
      }
    end)
  end

  # --- Constraint parsing ---

  defp parse_constraints(sections) do
    sections
    |> find_section("constraints")
    |> parse_list_items()
    |> Enum.map(fn item ->
      %{
        description: item,
        type: infer_constraint_type(item)
      }
    end)
  end

  # --- Acceptance test parsing ---

  defp parse_acceptance_tests(sections) do
    content = find_section(sections, "acceptance test")

    # Parse Given/When/Then blocks
    content
    |> String.split(~r/(?=^-\s|^\*\s|^Given\b)/m)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_test_block/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_test_block(block) do
    given = extract_field(block, ~r/(?:Given|When)[:\s]+(.+)/i)
    expected = extract_field(block, ~r/(?:Then|Expected)[:\s]+(.+)/i)

    if given do
      %{
        given: given,
        expected: expected || "",
        raw: block
      }
    else
      # Try bullet-point format
      case String.trim(block) do
        "" ->
          nil

        text ->
          %{
            given: text,
            expected: "",
            raw: block
          }
      end
    end
  end

  # --- Architecture parsing ---

  defp parse_architecture(sections) do
    content = find_section(sections, "architecture")

    %{
      raw: content,
      components: extract_code_blocks(content)
    }
  end

  # --- Helpers ---

  defp find_section(sections, partial_name) do
    normalized = String.downcase(partial_name)

    sections
    |> Enum.find(fn {title, _body} ->
      String.contains?(normalize_section_title(title), normalized)
    end)
    |> case do
      {_title, body} -> body
      nil -> ""
    end
  end

  defp parse_list_items(content) do
    content
    |> String.split(~r/^[-*]\s+/m)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp extract_capability_name(text) do
    case Regex.run(~r/^\*\*(.+?)\*\*/, text) do
      [_, name] -> name
      _ -> String.slice(text, 0..50)
    end
  end

  defp infer_constraint_type(text) do
    cond do
      String.contains?(text, "must not") or String.contains?(text, "never") -> :prohibition
      String.contains?(text, "must") or String.contains?(text, "required") -> :requirement
      String.contains?(text, "should") -> :recommendation
      true -> :general
    end
  end

  defp extract_field(text, regex) do
    case Regex.run(regex, text) do
      [_, value] -> String.trim(value)
      _ -> nil
    end
  end

  defp extract_code_blocks(content) do
    Regex.scan(~r/```(?:\w+)?\n(.*?)```/s, content)
    |> Enum.map(fn [_, block] -> String.trim(block) end)
  end
end
