defmodule Site.GitTest do
  use ExUnit.Case, async: true

  import Site.TestHelpers

  alias Site.{Git, View}

  @sha "a3f9c21" <> String.duplicate("b", 33)

  test "short/1 is the first seven characters" do
    assert Git.short(@sha) == "a3f9c21"
  end

  test "commit_url/1 points at the GitHub repository" do
    assert Git.commit_url(@sha) == "https://github.com/y0anfa/website/commit/" <> @sha
  end

  test "a file outside any repository has no commit" do
    file = Path.join(tmp_dir(), "note.md")
    File.write!(file, "x")
    assert Git.last_commit(file) == nil
  end

  test "a missing file or directory has no commit" do
    assert Git.last_commit(Path.join(tmp_dir(), "missing/none.md")) == nil
  end

  test "outside a repository there is no HEAD" do
    assert Git.head(tmp_dir()) == nil
    assert Git.head(Path.join(tmp_dir(), "missing")) == nil
  end

  test "HEAD of this repository is nil (no commits yet) or a sha with a dirty flag" do
    case Git.head(".") do
      nil -> :ok
      %{sha: sha, dirty?: dirty?} when is_boolean(dirty?) -> assert sha =~ ~r/\A[0-9a-f]{40,64}\z/
    end
  end

  describe "footer build info" do
    test "no git is unversioned, without a link" do
      assert View.build_info(nil) == %{label: "unversioned", href: nil}
    end

    test "a clean HEAD shows the short sha linked to the commit" do
      assert View.build_info(%{sha: @sha, dirty?: false}) ==
               %{label: "a3f9c21", href: Git.commit_url(@sha)}
    end

    test "a dirty tree adds -dirty" do
      assert %{label: "a3f9c21-dirty", href: href} = View.build_info(%{sha: @sha, dirty?: true})
      assert href == Git.commit_url(@sha)
    end
  end
end
