defmodule Site.DiagramTest do
  use ExUnit.Case, async: true

  alias Site.Diagram

  @css File.read!("assets/css/site.css")

  defp svg(source) do
    assert {:ok, html} = Diagram.render(source)
    html
  end

  defp count(html, pattern), do: length(Regex.scan(pattern, html))

  defp size(html) do
    [_, w, h] = Regex.run(~r/<svg [^>]*width="([\d.]+)" height="([\d.]+)"/, html)
    {elem(Float.parse(w), 0), elem(Float.parse(h), 0)}
  end

  describe "what comes out" do
    test "one figure holding one svg, sized, with a text alternative" do
      html = svg("graph TD\n  A[Client] -->|TLS| B[Server]")

      assert html =~
               ~r{\A<figure class="diagram"><svg viewBox="0 0 [\d.]+ [\d.]+" width="[\d.]+" height="[\d.]+" role="img" aria-label="Flowchart: Client to Server \(TLS\)">}

      assert String.ends_with?(html, "</svg></figure>")
    end

    test "classes only: no style, no colour, no font, no script, no link" do
      for source <- [
            "flowchart LR\n  A --> B{C} -.-> D[(E)]\n  subgraph S\n  D\n  end",
            "sequenceDiagram\n  A->>B: hi\n  Note over A,B: n\n  loop l\n  B-->>A: yo\n  end"
          ] do
        html = svg(source)
        refute html =~ "style"
        refute html =~ ~r/fill=|stroke=|font-|#[0-9a-f]{3,6}\b/
        refute html =~ ~r/<script|<a |href|<foreignObject|<image/
        refute html =~ ~r/\son\w+=/
      end
    end

    test "every class it writes has a rule in site.css" do
      html =
        svg(
          "flowchart TD\n  A --> B\n  A -.-> C\n  A ==> D\n  subgraph S\n  B\n  end\n  D -->|x| A"
        ) <>
          svg(
            "sequenceDiagram\n  A->>B: hi\n  Note over A: n\n  alt a\n  B-->>A: yo\n  else b\n  A-)B: z\n  end"
          )

      classes =
        ~r/class="([^"]+)"/
        |> Regex.scan(html)
        |> Enum.flat_map(fn [_, names] -> String.split(names) end)
        |> Enum.uniq()

      assert "d-node" in classes

      for class <- classes do
        assert @css =~ ~r/\.#{Regex.escape(class)}[\s,{]/, class
      end
    end

    test "the same source gives the same bytes" do
      source = "graph LR\n  A --> B --> C\n  C --> A"
      assert Diagram.render(source) == Diagram.render(source)
    end

    test "labels are escaped" do
      html = svg(~s(graph TD\n  A["<script>x</script> & 'q'"] -->|"<b>"| B))

      refute html =~ "<script"
      refute html =~ "<b>"
      assert html =~ "&lt;script&gt;x&lt;/script&gt; &amp; &#39;q&#39;"
      assert html =~ "&lt;b&gt;"
    end
  end

  describe "flowcharts" do
    test "graph and flowchart, top-down by default, or left to right" do
      for head <- ["graph", "graph TD", "graph TB", "flowchart TD", "flowchart LR"] do
        assert {:ok, _} = Diagram.render("#{head}\n  A --> B"), head
      end

      {w, h} = size(svg("graph TD\n  A --> B --> C"))
      assert h > w

      {w, h} = size(svg("graph LR\n  A --> B --> C"))
      assert w > h
    end

    test "the shapes: box, rounded, stadium, diamond, cylinder" do
      html = svg("graph TD\n  A[a] --> B(b) --> C([c]) --> D{d} --> E[(e)] --> F((f))")

      # a box, a rounded box and two stadiums are rects; a diamond and a cylinder are paths
      assert count(html, ~r/<rect class="d-node"/) == 4
      assert count(html, ~r/<path class="d-node"/) == 2
      for label <- ~w(a b c d e f), do: assert(html =~ ">#{label}</tspan>")
    end

    test "a node keeps its label however often it is named, and a bare id is its own label" do
      html = svg("graph TD\n  A[First] --> B\n  B --> A\n  A --> C")

      assert count(html, ~r/>First<\/tspan>/) == 1
      assert html =~ ">B</tspan>"
      assert count(html, ~r/class="d-node"/) == 3
    end

    test "arrows, plain lines, dotted and thick, with a label either way" do
      html =
        svg(
          "graph TD\n  A --> B\n  A --- C\n  A -.-> D\n  A ==> E\n  A -->|piped| F\n  A -- worded --> G"
        )

      assert count(html, ~r/class="d-edge d-dashed"/) == 1
      assert count(html, ~r/class="d-edge d-thick"/) == 1
      # every edge but the plain line has a head
      assert count(html, ~r/class="d-head"/) == 5
      assert html =~ ">piped</tspan>"
      assert html =~ ">worded</tspan>"
      assert count(html, ~r/class="d-mask"/) == 2
    end

    test "a subgraph is a dashed box round its nodes, with its title" do
      html = svg("graph TD\n  U --> W\n  subgraph Trust boundary\n    W --> D\n  end")

      assert count(html, ~r/class="d-group"/) == 1
      assert html =~ ~r{<text class="d-group-label"[^>]*>Trust boundary</text>}

      assert svg(
               "graph TD\n  subgraph one [The first]\n  A\n  end\n  subgraph two\n  B\n  end\n  A --> B"
             )
             |> count(~r/class="d-group"/) == 2
    end

    test "an edge that goes back up is drawn square, and nothing loops forever" do
      html = svg("graph TD\n  A --> B --> C\n  C --> A")
      assert html =~ ~r/<path class="d-edge" d="M[^"]* V[^"]* Q[^"]* H[^"]*"/
      assert {:ok, _} = Diagram.render("graph LR\n  A --> B\n  B --> A\n  A --> A")
    end

    test "comments, semicolons, a <br> and styling lines are taken in stride" do
      html =
        svg(
          "graph TD\n  %% a comment\n  A[one<br>two] --> B; B --> C\n  classDef x fill:#f00\n  style A fill:#f00"
        )

      assert html =~ ">one</tspan>"
      assert html =~ ">two</tspan>"
      refute html =~ "f00"
      refute html =~ "comment"
    end
  end

  describe "sequence diagrams" do
    test "participants in order of appearance, named with `as`" do
      html = svg("sequenceDiagram\n  participant B as Browser\n  B->>A: GET /\n  A-->>B: 200")

      assert count(html, ~r/<rect class="d-node"/) == 2
      assert count(html, ~r/class="d-life"/) == 2
      assert html =~ ">Browser</tspan>"
      assert html =~ ~s(aria-label="Sequence diagram: Browser to A: GET /; A to Browser: 200")
    end

    test "solid and dashed messages, filled and open heads, and a message to oneself" do
      html =
        svg(
          "sequenceDiagram\n  A->>B: one\n  B-->>A: two\n  A-)B: three\n  A->B: four\n  A->>A: think"
        )

      assert count(html, ~r/class="d-edge d-dashed"/) == 1
      assert count(html, ~r/class="d-head"/) == 3
      for word <- ~w(one two three four think), do: assert(html =~ ">#{word}</tspan>")
    end

    test "notes and frames" do
      html =
        svg(
          "sequenceDiagram\n  A->>B: x\n  Note over A,B: both\n  Note right of B: aside\n  alt ok\n    B-->>A: y\n  else not ok\n    B-->>A: z\n  end\n  loop retry\n    A->>B: again\n  end"
        )

      assert count(html, ~r/class="d-note"/) == 2
      assert count(html, ~r/class="d-frame"/) == 2
      assert html =~ ">alt ok</text>"
      assert html =~ ">not ok</text>"
      assert html =~ ">loop retry</text>"
    end
  end

  describe "what it refuses" do
    test "other diagram types, and nothing at all" do
      for source <- [
            "",
            "pie title x\n  \"a\": 1",
            "gantt\n  title x",
            "classDiagram\n  A <|-- B",
            "graph RL\n  A --> B",
            "hello"
          ] do
        assert Diagram.render(source) == :error, source
      end
    end

    test "a line that does not parse, an open block, a nested subgraph" do
      for source <- [
            "graph TD\n  A -->",
            "graph TD\n  A ~~~ B",
            "graph TD",
            "graph TD\n  subgraph S\n  A --> B",
            "graph TD\n  subgraph S\n  subgraph T\n  A\n  end\n  end",
            "graph TD\n  A --> B\n  end",
            "sequenceDiagram",
            "sequenceDiagram\n  A->>B: x\n  end",
            "sequenceDiagram\n  loop x\n  A->>B: x",
            "sequenceDiagram\n  Note sideways: x",
            "sequenceDiagram\n  just words"
          ] do
        assert Diagram.render(source) == :error, source
      end
    end
  end
end
