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
    case System.cmd("mix", ["compile", "--warnings-as-errors"],
           cd: build_dir,
           stderr_to_stdout: true
         ) do
      {output, 0} -> {:ok, output}
      {output, _} -> {:error, "Compilation failed:\n#{output}"}
    end
  end

  defp run_build("typescript", build_dir) do
    case System.cmd("npm", ["run", "build"],
           cd: build_dir,
           stderr_to_stdout: true
         ) do
      {output, 0} -> {:ok, output}
      {output, _} -> {:error, "Build failed:\n#{output}"}
    end
  end

  defp run_build("python", build_dir) do
    case System.cmd("python", ["-m", "py_compile", "."],
           cd: build_dir,
           stderr_to_stdout: true
         ) do
      {output, 0} -> {:ok, output}
      {output, _} -> {:error, "Build failed:\n#{output}"}
    end
  end

  defp run_build(framework, _build_dir) do
    {:error, "Unsupported framework: #{framework}"}
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
