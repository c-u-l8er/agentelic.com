defmodule Agentelic.Pipeline.Compiler do
  @moduledoc """
  Stage 3: COMPILE — build artifact compilation.

  Takes generated source files and compiles them into a deployable artifact.
  Shells out to framework-specific build tools (mix compile, npm run build, etc.).
  """

  alias Agentelic.Pipeline.Parser

  @type artifact :: %{
          hash: String.t(),
          path: String.t(),
          warnings: [String.t()],
          size_bytes: non_neg_integer()
        }

  @doc """
  Compile generated source files into a build artifact.

  Options:
    - `:build_dir` - directory to compile in (required)
    - `:framework` - target framework for build tool selection

  Returns `{:ok, artifact}` or `{:error, reason}`.
  """
  @spec compile([map()], keyword()) :: {:ok, artifact()} | {:error, String.t()}
  def compile(generated_files, opts \\ []) do
    build_dir = Keyword.get(opts, :build_dir, System.tmp_dir!())
    framework = Keyword.get(opts, :framework, "elixir")

    with :ok <- write_files(generated_files, build_dir),
         {:ok, output} <- run_build(framework, build_dir) do
      hash = compute_artifact_hash(build_dir)

      artifact = %{
        hash: hash,
        path: build_dir,
        warnings: extract_warnings(output),
        size_bytes: dir_size(build_dir)
      }

      {:ok, artifact}
    end
  end

  defp write_files(files, build_dir) do
    Enum.each(files, fn %{path: path, content: content} ->
      full_path = Path.join(build_dir, path)
      full_path |> Path.dirname() |> File.mkdir_p!()
      File.write!(full_path, content)
    end)

    :ok
  end

  defp run_build("elixir", build_dir) do
    # In-process syntax validation via Code.string_to_quoted/1.
    # This avoids requiring `mix` in the release container and keeps the
    # compile stage deterministic: same files → same result, no shell-out.
    files = Path.wildcard(Path.join(build_dir, "**/*.{ex,exs}"))

    errors =
      Enum.flat_map(files, fn path ->
        case path |> File.read!() |> Code.string_to_quoted(file: path) do
          {:ok, _ast} -> []
          {:error, {meta, msg, token}} -> ["#{path}:#{inspect(meta)} #{inspect(msg)} #{inspect(token)}"]
        end
      end)

    case errors do
      [] -> {:ok, "Validated #{length(files)} Elixir source file(s)"}
      _ -> {:error, "Syntax errors:\n" <> Enum.join(errors, "\n")}
    end
  end

  defp run_build("typescript", build_dir) do
    safe_cmd("npm", ["run", "build"], build_dir)
  end

  defp run_build("python", build_dir) do
    safe_cmd("python", ["-m", "py_compile", "."], build_dir)
  end

  defp run_build(framework, _build_dir) do
    {:error, "Unsupported framework: #{framework}"}
  end

  # Wrap System.cmd so a missing binary (ENOENT in a release container) or any
  # other shell-out failure becomes a tagged error instead of a Task crash that
  # leaves the build stuck in :compiling.
  defp safe_cmd(bin, args, build_dir) do
    {out, status} = System.cmd(bin, args, cd: build_dir, stderr_to_stdout: true)

    case status do
      0 -> {:ok, out}
      _ -> {:error, "#{bin} #{Enum.join(args, " ")} failed (exit #{status}):\n#{out}"}
    end
  rescue
    e in ErlangError ->
      case e.original do
        :enoent -> {:error, "#{bin} not available in build environment"}
        other -> {:error, "#{bin} failed: #{inspect(other)}"}
      end

    e ->
      {:error, "#{bin} failed: #{Exception.message(e)}"}
  end

  defp extract_warnings(output) do
    output
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, "warning"))
  end

  defp compute_artifact_hash(build_dir) do
    # Hash all source files in the build directory for determinism
    build_dir
    |> list_source_files()
    |> Enum.sort()
    |> Enum.map(&File.read!/1)
    |> Enum.join()
    |> Parser.compute_hash()
  end

  defp list_source_files(dir) do
    Path.wildcard(Path.join(dir, "**/*.{ex,exs,ts,js,py}"))
  end

  defp dir_size(dir) do
    dir
    |> list_source_files()
    |> Enum.reduce(0, fn path, acc ->
      case File.stat(path) do
        {:ok, %{size: size}} -> acc + size
        _ -> acc
      end
    end)
  end
end
