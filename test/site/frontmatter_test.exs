defmodule Site.FrontmatterTest do
  use ExUnit.Case, async: true

  alias Site.Frontmatter

  doctest Site.Frontmatter

  test "splits frontmatter and body" do
    source =
      "---\ntitle: Hello\ndate: 2026-10-28\ndraft: true\nstack: [Go, YAML]\n---\n\nBody *here*.\n"

    assert {:ok, meta, body} = Frontmatter.parse(source)

    assert meta == %{
             "title" => "Hello",
             "date" => "2026-10-28",
             "draft" => true,
             "stack" => ["Go", "YAML"]
           }

    assert body == "\nBody *here*.\n"
  end

  test "handles CRLF line endings and a BOM" do
    assert {:ok, %{"title" => "Hi"}, "text\n"} =
             Frontmatter.parse("﻿---\r\ntitle: Hi\r\n---\r\ntext\r\n")
  end

  test "a --- inside a value does not close the block" do
    assert {:ok, %{"title" => "a---b"}, "x"} = Frontmatter.parse("---\ntitle: a---b\n---\nx")
  end

  test "an empty frontmatter block is an empty map" do
    assert {:ok, %{}, "x"} = Frontmatter.parse("---\n---\nx")
  end

  test "horizontal rules in the body are kept" do
    assert {:ok, _, "a\n---\nb"} = Frontmatter.parse("---\ntitle: t\n---\na\n---\nb")
  end

  test "reports a missing opening fence" do
    assert {:error, message} = Frontmatter.parse("# No frontmatter\n")
    assert message =~ "missing frontmatter"
    assert {:error, message} = Frontmatter.parse("")
    assert message =~ "missing frontmatter"
  end

  test "reports an unterminated block" do
    assert {:error, message} = Frontmatter.parse("---\ntitle: t\nbody\n")
    assert message =~ "unterminated"
  end

  test "reports invalid YAML and non-mapping YAML" do
    assert {:error, message} = Frontmatter.parse("---\ntitle: [unclosed\n---\n")
    assert message =~ "invalid YAML"
    assert {:error, message} = Frontmatter.parse("---\n- a\n- b\n---\n")
    assert message =~ "mapping"
  end
end
