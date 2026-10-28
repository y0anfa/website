defmodule Site.Git do
  @moduledoc """
  Reads git facts for the build: the last commit that touched a file (for log
  hashes) and the HEAD commit (for the footer).

  Everything degrades to `nil`: no git binary, no repository, no commits yet,
  an untracked file. The caller shows `·······` or `unversioned` instead.
  """

  @sha ~r/\A[0-9a-f]{40}(?:[0-9a-f]{24})?\z/

  @doc "Full sha of the last commit touching `file`, or `nil`."
  @spec last_commit(Path.t()) :: String.t() | nil
  def last_commit(file) do
    file = Path.expand(file)

    case git(["log", "-1", "--format=%H", "--", Path.basename(file)], Path.dirname(file)) do
      {:ok, out} -> sha(out)
      :error -> nil
    end
  end

  @doc """
  The HEAD commit of the repository at `dir`: `%{sha: sha, dirty?: boolean}`, or
  `nil` when there is no git, no repository or no commit yet. `dirty?` is true
  when tracked files differ from HEAD (untracked files do not count).
  """
  @spec head(Path.t()) :: %{sha: String.t(), dirty?: boolean()} | nil
  def head(dir \\ ".") do
    with {:ok, out} <- git(["rev-parse", "--verify", "--quiet", "HEAD"], dir),
         sha when is_binary(sha) <- sha(out) do
      dirty? =
        case git(["status", "--porcelain", "--untracked-files=no"], dir) do
          {:ok, status} -> String.trim(status) != ""
          :error -> false
        end

      %{sha: sha, dirty?: dirty?}
    else
      _ -> nil
    end
  end

  @doc "First seven characters of a sha."
  @spec short(String.t()) :: String.t()
  def short(sha), do: String.slice(sha, 0, 7)

  @doc "GitHub URL of a commit."
  @spec commit_url(String.t()) :: String.t()
  def commit_url(sha), do: Site.Config.repo_url() <> "/commit/" <> sha

  defp sha(output) do
    output = String.trim(output)
    if Regex.match?(@sha, output), do: output
  end

  defp git(args, dir) do
    if File.dir?(dir), do: run(args, dir), else: :error
  end

  defp run(args, dir) do
    opts = [
      cd: dir,
      stderr_to_stdout: true,
      env: [{"GIT_TERMINAL_PROMPT", "0"}, {"GIT_PAGER", "cat"}, {"LC_ALL", "C"}]
    ]

    case System.cmd("git", args, opts) do
      {out, 0} -> {:ok, out}
      {_out, _status} -> :error
    end
  rescue
    # the git binary is not installed
    ErlangError -> :error
  end
end
