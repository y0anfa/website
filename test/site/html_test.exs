defmodule Site.HTMLTest do
  use ExUnit.Case, async: true

  import Site.HTML

  doctest Site.HTML

  test "escapes the five dangerous characters once" do
    assert escape(~s(<a href="x" title='y'>&amp;</a>)) ==
             "&lt;a href=&quot;x&quot; title=&#39;y&#39;&gt;&amp;amp;&lt;/a&gt;"
  end

  test "leaves safe text alone, including non-ASCII" do
    assert escape("Yoan Faure — security engineer · Paris") ==
             "Yoan Faure — security engineer · Paris"
  end

  test "handles nil, dates, numbers and atoms" do
    assert escape(nil) == ""
    assert escape(~D[2026-10-28]) == "2026-10-28"
    assert escape(42) == "42"
    assert escape(:essay) == "essay"
  end

  test "raw passes binaries through untouched" do
    assert raw("<p>ok</p>") == "<p>ok</p>"
  end
end
