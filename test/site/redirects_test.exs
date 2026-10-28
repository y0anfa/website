defmodule Site.RedirectsTest do
  use ExUnit.Case, async: true

  alias Site.{Config, Redirects}

  test "the file sends the old Hugo URLs to the flat ones" do
    assert Redirects.render() == """
           /blog/* /:splat 301
           /projects/* /:splat 301
           /resume/ / 301
           /resume / 301
           """
  end

  test "every line is `from to status`, permanent, with an absolute path on both sides" do
    lines = Redirects.render() |> String.split("\n", trim: true)
    assert length(lines) == length(Config.redirects())

    for line <- lines do
      assert [from, to, "301"] = String.split(line, " ")
      assert String.starts_with?(from, "/")
      assert String.starts_with?(to, "/")
    end
  end

  test "the output is the same every time" do
    assert Redirects.render() == Redirects.render()
    refute Redirects.render() =~ ~r/\d{4}-\d{2}-\d{2}/
  end

  test "the old essay URL lands on the new one" do
    # /blog/threat-modeling-with-claude-code/ -> /:splat -> /threat-modeling-with-claude-code/
    assert {"/blog/*", "/:splat", 301} in Config.redirects()

    assert Site.Content.slug("2026-03-28-threat-modeling-with-claude-code.md") ==
             "threat-modeling-with-claude-code"
  end

  describe "reserved slugs" do
    test "cover the files and directories the build writes" do
      for slug <- ~w(assets 404 index robots.txt _headers _redirects) do
        assert slug in Config.reserved_slugs(), "#{slug} is not reserved"
      end
    end

    test "cover the top-level names the legacy redirects take over" do
      for slug <- ~w(blog projects resume) do
        assert slug in Config.reserved_slugs(), "#{slug} is not reserved"
      end
    end

    test "are sorted and unique" do
      slugs = Config.reserved_slugs()
      assert slugs == slugs |> Enum.uniq() |> Enum.sort()
    end
  end

  describe "entry types" do
    test "the content directory sets the type, and nothing else" do
      assert Config.types() |> Enum.map(&Config.dir/1) |> Enum.sort() ==
               ["essays", "notes", "projects"]
    end

    test "the sort rank is essay, project, note" do
      assert Enum.sort_by(Config.types(), &Config.rank/1) == [:essay, :project, :note]
    end
  end
end
