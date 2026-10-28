defmodule Site.Frontmatter do
  @moduledoc """
  Splits a Markdown source into YAML frontmatter and body.

  The file must start with a `---` line, followed by YAML, followed by a closing
  `---` line. Keys are returned as strings.
  """

  @type t :: %{String.t() => term()}

  @doc """
  Returns `{:ok, meta, body}` or `{:error, message}`.

      iex> Site.Frontmatter.parse("---\\ntitle: Hi\\n---\\nbody\\n")
      {:ok, %{"title" => "Hi"}, "body\\n"}
  """
  @spec parse(String.t()) :: {:ok, t(), String.t()} | {:error, String.t()}
  def parse(source) when is_binary(source) do
    lines =
      source
      |> String.trim_leading("﻿")
      |> String.replace("\r\n", "\n")
      |> String.split("\n")

    with {:ok, rest} <- opening(lines),
         {:ok, yaml_lines, body_lines} <- closing(rest),
         {:ok, meta} <- yaml(Enum.join(yaml_lines, "\n")) do
      {:ok, meta, Enum.join(body_lines, "\n")}
    end
  end

  defp opening([first | rest]) do
    if fence?(first),
      do: {:ok, rest},
      else: {:error, "missing frontmatter (expected a leading ---)"}
  end

  defp closing(lines) do
    case Enum.split_while(lines, &(not fence?(&1))) do
      {yaml, [_fence | body]} -> {:ok, yaml, body}
      {_all, []} -> {:error, "unterminated frontmatter (expected a closing ---)"}
    end
  end

  defp fence?(line), do: String.trim_trailing(line) == "---"

  defp yaml(string) do
    case YamlElixir.read_from_string(string) do
      {:ok, meta} when is_map(meta) -> {:ok, meta}
      {:ok, _} -> {:error, "frontmatter must be a YAML mapping (key: value)"}
      {:error, %{message: message}} -> {:error, "invalid YAML in frontmatter: #{message}"}
      {:error, other} -> {:error, "invalid YAML in frontmatter: #{inspect(other)}"}
    end
  end
end
