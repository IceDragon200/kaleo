defmodule Kaleo.Core.Util do
  @type path_segment :: String.t()

  @type path_match_pattern :: [:any_segment | :any_path | path_segment()]

  @spec handle_unresolved_path(Path.t(), Path.t()) :: Path.t()
  def handle_unresolved_path(unresolved_path, parent_dirname) do
    unresolved_path_parts = Path.split(unresolved_path)

    resolved_path =
      Enum.map(unresolved_path_parts, fn
        "@" ->
          parent_dirname

        part ->
          part
      end)

    resolved_path
    |> Path.join()
    |> Path.expand("/")
  end

  @spec parse_path_match_pattern(Path.t(), Path.t()) :: path_match_pattern()
  def parse_path_match_pattern(pattern, parent_dirname) do
    pattern_parts = Path.split(pattern)

    resolved_path =
      Enum.map(pattern_parts, fn
        "@" ->
          parent_dirname

        part ->
          part
      end)

    resolved_path =
      resolved_path
      |> Path.join()
      |> Path.expand("/")
      |> Path.split()
      |> Enum.map(fn
        "*" ->
          :any_segment

        "**" ->
          :any_path

        path ->
          path
      end)

    resolved_path
  end

  def paths_match?(
    host_path,
    pattern
  ) when is_list(host_path) and is_list(pattern) do
    do_paths_match?(host_path, pattern)
  end

  def paths_match?(
    host_path,
    pattern
  ) when is_binary(host_path) do
    paths_match?(Path.split(host_path), pattern)
  end

  def paths_match?(
    host_path,
    pattern
  ) when is_binary(pattern) do
    paths_match?(host_path, Path.split(pattern))
  end

  defp do_paths_match?([segment | host_rest], [segment | pattern_rest]) when is_binary(segment) do
    do_paths_match?(host_rest, pattern_rest)
  end

  defp do_paths_match?([_segment | host_rest], [:any_segment | pattern_rest]) do
    do_paths_match?(host_rest, pattern_rest)
  end

  defp do_paths_match?([], []) do
    true
  end

  defp do_paths_match?(_host_path, _pattern) do
    false
  end
end
