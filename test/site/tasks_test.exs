defmodule Site.TasksTest do
  use ExUnit.Case, async: false

  import Site.TestHelpers

  setup do
    previous = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(previous) end)
    :ok
  end

  defp infos do
    Stream.repeatedly(fn ->
      receive do
        {:mix_shell, :info, [message]} -> message
      after
        0 -> nil
      end
    end)
    |> Enum.take_while(& &1)
  end

  describe "mix site.build" do
    test "builds into --out from --content" do
      out = Path.join(tmp_dir(), "dist")
      Mix.Tasks.Site.Build.run(["--content", fixture_copy(), "--out", out])

      assert File.exists?(Path.join(out, "index.html"))
      assert Enum.any?(infos(), &(&1 =~ ~r/^site\.build: wrote \d+ files to /))
    end

    test "--drafts includes drafts" do
      out = Path.join(tmp_dir(), "dist")
      Mix.Tasks.Site.Build.run(["--drafts", "--content", fixture_copy(), "--out", out])
      assert File.exists?(Path.join(out, "an-unfinished-draft/index.html"))
    end

    test "content errors become a Mix error listing the problems" do
      out = Path.join(tmp_dir(), "dist")
      bad = minimal_content(%{"notes/n.md" => "---\ntitle: x\n---\n"})

      error =
        assert_raise Mix.Error, fn ->
          Mix.Tasks.Site.Build.run(["--content", bad, "--out", out])
        end

      assert error.message =~ "missing required field `date`"
    end

    test "unknown options are rejected" do
      assert_raise OptionParser.ParseError, fn -> Mix.Tasks.Site.Build.run(["--nope"]) end
    end
  end

  describe "mix site.verify" do
    test "builds twice, prints the tree hash" do
      Mix.Tasks.Site.Verify.run(["--content", fixture_copy()])

      assert Enum.any?(infos(), &(&1 =~ ~r/deterministic, tree hash [0-9a-f]{64}$/))
    end

    test "leaves no temporary directories behind" do
      before = tmp_verify_dirs()
      Mix.Tasks.Site.Verify.run(["--content", fixture_copy()])
      assert tmp_verify_dirs() == before
    end

    test "bad content is a Mix error" do
      bad = minimal_content(%{"notes/n.md" => "---\ntitle: x\n---\n"})
      assert_raise Mix.Error, ~r/date/, fn -> Mix.Tasks.Site.Verify.run(["--content", bad]) end
    end
  end

  defp tmp_verify_dirs, do: Path.wildcard(Path.join(System.tmp_dir!(), "site-verify-*"))
end
