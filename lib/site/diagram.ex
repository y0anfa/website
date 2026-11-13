defmodule Site.Diagram do
  @moduledoc """
  Draws a diagram from a subset of Mermaid syntax, as inline SVG, at build time.

  Two kinds are understood (SPEC section 5, Diagrams):

    * flowcharts: `graph TD` or `flowchart LR`, nodes in the usual shapes, arrows
      with or without a label, and one level of `subgraph`;
    * sequence diagrams: `sequenceDiagram`, participants, messages, notes and
      `loop` / `opt` / `alt` / `par` frames.

  The SVG carries classes only: no colour, no font and no `style` attribute, so
  `site.css` draws it in the page's ink, in both themes, under the strict CSP.
  Text is measured by a table of average glyph widths, not a font, so the output
  is the same on every machine.

  Anything else (another diagram type, a line that does not parse) is an
  `:error`: the caller keeps the block as code, so a typo shows up instead of
  vanishing.
  """

  import Site.HTML, only: [escape: 1]

  @type result :: {:ok, String.t()} | :error

  @font 14
  @small 12
  @line 20
  @pad 8

  @doc "Renders Mermaid source to a `<figure class=\"diagram\">`, or `:error`."
  @spec render(String.t()) :: result()
  def render(source) when is_binary(source) do
    lines =
      source
      |> String.split(["\n", ";"])
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "%%")))

    case lines do
      [head | rest] ->
        cond do
          match = Regex.run(~r/^(?:graph|flowchart)(?:\s+(TD|TB|LR))?$/, head) ->
            flow(rest, if(Enum.at(match, 1) == "LR", do: :lr, else: :td))

          head == "sequenceDiagram" ->
            sequence(rest)

          true ->
            :error
        end

      [] ->
        :error
    end
  catch
    :bad -> :error
  end

  # -- text -------------------------------------------------------------------

  # The width of a line of text in px, from average glyph widths of Inter.
  defp width(text, size) do
    text
    |> String.graphemes()
    |> Enum.reduce(0.0, fn g, sum -> sum + glyph(g) end)
    |> Kernel.*(size)
  end

  @narrow String.graphemes("iljtfrI.,:;'|!()[]")
  @wide String.graphemes("mwMW@")

  defp glyph(" "), do: 0.3
  defp glyph(g) when g in @narrow, do: 0.34
  defp glyph(g) when g in @wide, do: 0.88
  defp glyph(g), do: if(g =~ ~r/^[A-Z0-9]$/, do: 0.68, else: 0.57)

  # A label is one or more lines: Mermaid breaks them with <br>.
  defp label(text) do
    text
    |> String.trim()
    |> String.trim("\"")
    |> String.split(~r{<br\s*/?>})
    |> Enum.map(&String.trim/1)
  end

  defp widest(lines, size \\ @font), do: lines |> Enum.map(&width(&1, size)) |> Enum.max()

  # -- svg --------------------------------------------------------------------

  # Numbers with one decimal at most, so the output is short and stable.
  defp n(value) when is_integer(value), do: Integer.to_string(value)

  defp n(value) do
    rounded = Float.round(value * 1.0, 1)
    if rounded == trunc(rounded), do: Integer.to_string(trunc(rounded)), else: "#{rounded}"
  end

  defp text(lines, x, y, class) do
    top = y - (length(lines) - 1) * @line / 2

    spans =
      lines
      |> Enum.with_index()
      |> Enum.map_join(fn {line, i} ->
        ~s(<tspan x="#{n(x)}" y="#{n(top + i * @line)}">#{escape(line)}</tspan>)
      end)

    ~s(<text class="#{class}" text-anchor="middle" dominant-baseline="central">#{spans}</text>)
  end

  defp rect(x, y, w, h, class, radius \\ 0) do
    ~s(<rect class="#{class}" x="#{n(x)}" y="#{n(y)}" width="#{n(w)}" height="#{n(h)}" rx="#{n(radius)}"/>)
  end

  # An arrowhead at `tip`, pointing the way `from` -> `tip` goes.
  defp head({tx, ty}, {fx, fy}, open? \\ false) do
    {dx, dy} = {tx - fx, ty - fy}
    len = max(:math.sqrt(dx * dx + dy * dy), 0.001)
    {ux, uy} = {dx / len, dy / len}
    {bx, by} = {tx - ux * 9, ty - uy * 9}
    a = "#{n(bx - uy * 4)} #{n(by + ux * 4)}"
    b = "#{n(bx + uy * 4)} #{n(by - ux * 4)}"

    if open?,
      do: ~s(<path class="d-edge" d="M#{a} L#{n(tx)} #{n(ty)} L#{b}"/>),
      else: ~s(<path class="d-head" d="M#{n(tx)} #{n(ty)} L#{a} L#{b} Z"/>)
  end

  defp figure(body, w, h, summary) do
    ~s(<figure class="diagram"><svg viewBox="0 0 #{n(w)} #{n(h)}" width="#{n(w)}" height="#{n(h)}" role="img" aria-label="#{escape(summary)}">) <>
      body <> "</svg></figure>"
  end

  # == flowcharts =============================================================

  @shapes [
    {"([", "])", :stadium},
    {"[(", ")]", :cylinder},
    {"((", "))", :stadium},
    {"[", "]", :rect},
    {"(", ")", :round},
    {"{", "}", :diamond}
  ]

  @ignored ~w(classDef class style linkStyle click direction)

  defp flow(lines, dir) do
    start = %{nodes: %{}, order: [], edges: [], groups: [], group: nil}
    graph = Enum.reduce(lines, start, &flow_line/2)
    if graph.group != nil or graph.order == [], do: throw(:bad)

    graph = %{graph | order: Enum.reverse(graph.order), edges: Enum.reverse(graph.edges)}
    draw_flow(graph, dir)
  end

  defp flow_line(line, graph) do
    [word | _] = String.split(line, ~r/\s+/, parts: 2)

    cond do
      word in @ignored ->
        graph

      word == "subgraph" ->
        if graph.group != nil, do: throw(:bad)
        title = line |> String.replace_prefix("subgraph", "") |> subgraph_title()
        index = length(graph.groups)
        %{graph | groups: graph.groups ++ [title], group: index}

      line == "end" ->
        if graph.group == nil, do: throw(:bad)
        %{graph | group: nil}

      true ->
        {id, rest, graph} = flow_node(line, graph)
        flow_chain(id, rest, graph)
    end
  end

  # `subgraph Title`, `subgraph id [Title]` or `subgraph "Title"`.
  defp subgraph_title(rest) do
    rest = String.trim(rest)

    case Regex.run(~r/^\w+\s*\[(.+)\]$/, rest) do
      [_, title] -> label(title)
      nil -> if rest == "", do: throw(:bad), else: label(rest)
    end
  end

  defp flow_chain(_from, "", graph), do: graph

  defp flow_chain(from, rest, graph) do
    {kind, text, rest} = flow_edge(rest)
    {to, rest, graph} = flow_node(rest, graph)
    edge = %{from: from, to: to, kind: kind, label: text}
    flow_chain(to, rest, %{graph | edges: [edge | graph.edges]})
  end

  @edges [
    {~r/^-{2,}>/, :arrow},
    {~r/^-{3,}/, :line},
    {~r/^-\.+->/, :dotted},
    {~r/^-\.+-/, :dotted_line},
    {~r/^={2,}>/, :thick}
  ]

  @worded [
    {~r/^--\s+(.+?)\s+-{2,}>/, :arrow},
    {~r/^--\s+(.+?)\s+-{3,}/, :line},
    {~r/^-\.\s+(.+?)\s+\.+->/, :dotted},
    {~r/^==\s+(.+?)\s+={2,}>/, :thick}
  ]

  # An edge at the start of `rest`: its kind, its label (or nil), and what follows.
  defp flow_edge(rest) do
    worded =
      Enum.find_value(@worded, fn {pattern, kind} ->
        case Regex.run(pattern, rest) do
          [whole, words] -> {kind, label(words), after_match(rest, whole)}
          nil -> nil
        end
      end)

    plain = fn ->
      Enum.find_value(@edges, fn {pattern, kind} ->
        case Regex.run(pattern, rest) do
          [whole] -> piped(kind, after_match(rest, whole))
          nil -> nil
        end
      end)
    end

    worded || plain.() || throw(:bad)
  end

  # `-->|label| B`
  defp piped(kind, rest) do
    case Regex.run(~r/^\|([^|]*)\|/, rest) do
      [whole, words] -> {kind, label(words), after_match(rest, whole)}
      nil -> {kind, nil, rest}
    end
  end

  defp after_match(rest, whole) do
    rest |> binary_part(byte_size(whole), byte_size(rest) - byte_size(whole)) |> String.trim()
  end

  # A node at the start of `text`: its id, an optional shape with its label.
  defp flow_node(text, graph) do
    [whole, id] = Regex.run(~r/^([A-Za-z0-9_]+)/, text) || throw(:bad)
    rest = binary_part(text, byte_size(whole), byte_size(text) - byte_size(whole))

    shaped =
      Enum.find_value(@shapes, fn {open, close, shape} ->
        with true <- String.starts_with?(rest, open),
             inner = String.replace_prefix(rest, open, ""),
             [words, tail] <- String.split(inner, close, parts: 2) do
          {shape, label(words), tail}
        else
          _ -> nil
        end
      end)

    {shape, lines, rest} = shaped || {nil, nil, rest}
    known = graph.nodes[id]

    node =
      cond do
        known && shape -> %{known | shape: shape, label: lines}
        known -> known
        true -> %{shape: shape || :rect, label: lines || [id], group: graph.group}
      end

    order = if known, do: graph.order, else: [id | graph.order]
    {id, String.trim(rest), %{graph | nodes: Map.put(graph.nodes, id, node), order: order}}
  end

  # -- flowchart layout ---------------------------------------------------------

  defp draw_flow(graph, dir) do
    nodes = Map.new(graph.nodes, fn {id, node} -> {id, Map.merge(node, node_size(node))} end)
    edges = Enum.reject(graph.edges, &(&1.from == &1.to))
    ranks = ranks(graph.order, edges)
    layers = layers(graph.order, edges, ranks, nodes)
    places = place(layers, nodes, graph.order, dir)
    labelled? = Enum.any?(edges, & &1.label)

    # every node's box in page coordinates
    boxes =
      Map.new(places, fn {id, {b, d}} ->
        node = nodes[id]
        {x, y} = if dir == :td, do: {b, d}, else: {d, b}
        {id, %{x: x, y: y, w: node.w, h: node.h}}
      end)

    groups =
      graph.groups
      |> Enum.with_index()
      |> Enum.flat_map(fn {title, index} ->
        case for {id, node} <- nodes, node.group == index, do: boxes[id] do
          [] ->
            []

          members ->
            x0 = members |> Enum.map(& &1.x) |> Enum.min()
            y0 = members |> Enum.map(& &1.y) |> Enum.min()
            x1 = members |> Enum.map(&(&1.x + &1.w)) |> Enum.max()
            y1 = members |> Enum.map(&(&1.y + &1.h)) |> Enum.max()
            w = max(x1 - x0 + 28, widest(title, @small) + 28)
            [%{title: title, x: x0 - 14, y: y0 - 32, w: w, h: y1 - y0 + 46}]
        end
      end)

    # shift everything so the drawing starts at the padding
    all = Map.values(boxes) ++ groups
    left = all |> Enum.map(& &1.x) |> Enum.min()
    top = all |> Enum.map(& &1.y) |> Enum.min()
    extra = if labelled?, do: 24, else: 0
    shift = fn box -> %{box | x: box.x - left + @pad + extra, y: box.y - top + @pad} end
    boxes = Map.new(boxes, fn {id, box} -> {id, shift.(box)} end)
    groups = Enum.map(groups, shift)

    all = Map.values(boxes) ++ groups
    # back edges go round the nodes between their ends, 40px out
    back? = Enum.any?(edges, &(ranks[&1.to] < ranks[&1.from]))
    {round, past} = if back?, do: {48, 30}, else: {0, 0}
    {more_w, more_h} = if dir == :td, do: {round, past}, else: {past, round}
    w = (all |> Enum.map(&(&1.x + &1.w)) |> Enum.max()) + @pad + extra + more_w
    h = (all |> Enum.map(&(&1.y + &1.h)) |> Enum.max()) + @pad + more_h

    body =
      Enum.map_join(groups, &draw_group/1) <>
        Enum.map_join(edges, &draw_edge(&1, boxes, ranks, dir)) <>
        Enum.map_join(groups, &draw_group_title/1) <>
        Enum.map_join(graph.order, &draw_node(nodes[&1], boxes[&1]))

    summary =
      "Flowchart: " <>
        Enum.map_join(edges, "; ", fn edge ->
          from = Enum.join(nodes[edge.from].label, " ")
          to = Enum.join(nodes[edge.to].label, " ")
          via = if edge.label, do: " (#{Enum.join(edge.label, " ")})", else: ""
          "#{from} to #{to}#{via}"
        end)

    {:ok, figure(body, w, h, summary)}
  end

  defp node_size(%{label: lines, shape: shape}) do
    w = max(72, widest(lines) + 36)
    h = 40 + (length(lines) - 1) * @line

    case shape do
      :diamond -> %{w: w + 36, h: h + 20}
      :cylinder -> %{w: w, h: h + 10}
      _ -> %{w: w, h: h}
    end
  end

  # The rank of each node: the longest path to it, back edges of a cycle left out.
  defp ranks(order, edges) do
    out = Enum.group_by(edges, & &1.from, & &1.to)

    {_, _, back} =
      Enum.reduce(order, {MapSet.new(), MapSet.new(), MapSet.new()}, fn id, acc ->
        visit(id, out, acc)
      end)

    forward = Enum.reject(edges, &MapSet.member?(back, {&1.from, &1.to}))
    into = Enum.group_by(forward, & &1.to, & &1.from)

    Enum.reduce(order, %{}, fn id, memo -> elem(rank(id, into, memo), 1) end)
  end

  defp visit(id, out, {done, stack, back} = acc) do
    if MapSet.member?(done, id) do
      acc
    else
      stack = MapSet.put(stack, id)

      {done, stack, back} =
        Enum.reduce(Map.get(out, id, []), {done, stack, back}, fn to, {done, stack, back} ->
          cond do
            MapSet.member?(stack, to) -> {done, stack, MapSet.put(back, {id, to})}
            true -> visit(to, out, {done, stack, back})
          end
        end)

      {MapSet.put(done, id), MapSet.delete(stack, id), back}
    end
  end

  defp rank(id, into, memo) do
    case memo do
      %{^id => value} ->
        {value, memo}

      _ ->
        {value, memo} =
          Enum.reduce(Map.get(into, id, []), {0, memo}, fn from, {best, memo} ->
            {r, memo} = rank(from, into, memo)
            {max(best, r + 1), memo}
          end)

        {value, Map.put(memo, id, value)}
    end
  end

  # The nodes of each rank, in order: by subgraph first (so a subgraph's nodes stay
  # together), then under the middle of the nodes that lead to them.
  defp layers(order, edges, ranks, nodes) do
    into = Enum.group_by(edges, & &1.to, & &1.from)
    bands = bands(order, nodes)
    last = ranks |> Map.values() |> Enum.max()

    {layers, _} =
      Enum.reduce(0..last, {[], %{}}, fn r, {layers, index} ->
        ids = Enum.filter(order, &(ranks[&1] == r))

        sorted =
          ids
          |> Enum.with_index()
          |> Enum.sort_by(fn {id, i} ->
            above = for from <- Map.get(into, id, []), pos = index[from], do: pos
            mean = if above == [], do: i * 1.0, else: Enum.sum(above) / length(above)
            {Map.fetch!(bands, nodes[id].group), mean, i}
          end)
          |> Enum.map(&elem(&1, 0))

        index =
          sorted
          |> Enum.with_index()
          |> Enum.reduce(index, fn {id, i}, acc -> Map.put(acc, id, i) end)

        {[sorted | layers], index}
      end)

    Enum.reverse(layers)
  end

  # Bands: one per subgraph and one for the nodes outside any, in order of first use.
  defp bands(order, nodes) do
    order
    |> Enum.map(&nodes[&1].group)
    |> Enum.uniq()
    |> Enum.with_index()
    |> Map.new()
  end

  # Where each node goes, as {breadth, depth}: breadth runs along a rank, depth
  # from rank to rank. A band is as broad as its broadest rank, and each rank's
  # nodes are centred in it, so two subgraphs never overlap.
  defp place(layers, nodes, order, dir) do
    {gap, band_gap, depth_gap} = if dir == :td, do: {28, 48, 60}, else: {20, 56, 76}
    breadth = fn id -> if dir == :td, do: nodes[id].w, else: nodes[id].h end
    depth = fn id -> if dir == :td, do: nodes[id].h, else: nodes[id].w end
    bands = bands(order, nodes)
    span = fn ids -> Enum.sum(Enum.map(ids, breadth)) + gap * max(length(ids) - 1, 0) end

    band_width =
      Map.new(bands, fn {group, band} ->
        widths =
          for layer <- layers,
              ids = Enum.filter(layer, &(nodes[&1].group == group)),
              ids != [],
              do: span.(ids)

        {band, Enum.max(widths, fn -> 0 end)}
      end)

    {band_start, _} =
      band_width
      |> Enum.sort()
      |> Enum.reduce({%{}, 0}, fn {band, w}, {starts, at} ->
        {Map.put(starts, band, at), at + w + band_gap}
      end)

    {places, _} =
      Enum.reduce(layers, {%{}, 0}, fn layer, {places, d} ->
        places =
          layer
          |> Enum.group_by(&Map.fetch!(bands, nodes[&1].group))
          |> Enum.reduce(places, fn {band, ids}, places ->
            start = band_start[band] + (band_width[band] - span.(ids)) / 2

            {places, _} =
              Enum.reduce(ids, {places, start}, fn id, {places, b} ->
                {Map.put(places, id, {b, d}), b + breadth.(id) + gap}
              end)

            places
          end)

        deepest = layer |> Enum.map(depth) |> Enum.max()
        # every node of a rank is centred on the rank's middle
        places =
          Enum.reduce(layer, places, fn id, places ->
            Map.update!(places, id, fn {b, d} -> {b, d + (deepest - depth.(id)) / 2} end)
          end)

        {places, d + deepest + depth_gap}
      end)

    places
  end

  # -- flowchart drawing --------------------------------------------------------

  defp draw_group(%{x: x, y: y, w: w, h: h}), do: rect(x, y, w, h, "d-group", 10)

  # Over the edges, on a patch of the page colour: an edge that comes into the
  # subgraph from above never runs through its title.
  defp draw_group_title(%{title: title, x: x, y: y}) do
    words = Enum.join(title, " ")

    rect(x + 8, y + 6, width(words, @small) + 10, @line, "d-mask") <>
      ~s(<text class="d-group-label" x="#{n(x + 12)}" y="#{n(y + 16)}" dominant-baseline="central">#{escape(words)}</text>)
  end

  defp draw_node(node, %{x: x, y: y, w: w, h: h}) do
    {cx, cy} = {x + w / 2, y + h / 2}

    shape =
      case node.shape do
        :rect ->
          rect(x, y, w, h, "d-node", 6)

        :round ->
          rect(x, y, w, h, "d-node", 14)

        :stadium ->
          rect(x, y, w, h, "d-node", h / 2)

        :diamond ->
          ~s(<path class="d-node" d="M#{n(cx)} #{n(y)} L#{n(x + w)} #{n(cy)} L#{n(cx)} #{n(y + h)} L#{n(x)} #{n(cy)} Z"/>)

        :cylinder ->
          r = "#{n(w / 2)} 6"

          ~s(<path class="d-node" d="M#{n(x)} #{n(y + 6)} A#{r} 0 0 1 #{n(x + w)} #{n(y + 6)} V#{n(y + h - 6)} A#{r} 0 0 1 #{n(x)} #{n(y + h - 6)} Z"/>) <>
            ~s(<path class="d-edge" d="M#{n(x)} #{n(y + 6)} A#{r} 0 0 0 #{n(x + w)} #{n(y + 6)}"/>)
      end

    shape <> text(node.label, cx, if(node.shape == :cylinder, do: cy + 4, else: cy), "d-label")
  end

  defp draw_edge(edge, boxes, ranks, dir) do
    {a, b} = {boxes[edge.from], boxes[edge.to]}
    step = ranks[edge.to] - ranks[edge.from]
    mid = fn box -> {box.x + box.w / 2, box.y + box.h / 2} end
    {{ax, ay}, {bx, by}} = {mid.(a), mid.(b)}

    # the path, the point its arrowhead comes from, its tip, and where a label sits
    {d, from, tip, at} =
      case {dir, step} do
        {:td, step} when step > 0 ->
          {sy, ey} = {a.y + a.h, b.y}
          curve({ax, sy}, {ax, (sy + ey) / 2}, {bx, (sy + ey) / 2}, {bx, ey})

        {:lr, step} when step > 0 ->
          {sx, ex} = {a.x + a.w, b.x}
          curve({sx, ay}, {(sx + ex) / 2, ay}, {(sx + ex) / 2, by}, {ex, by})

        {:td, 0} ->
          {sx, ex} = if bx > ax, do: {a.x + a.w, b.x}, else: {a.x, b.x + b.w}
          curve({sx, ay}, {(sx + ex) / 2, ay}, {(sx + ex) / 2, by}, {ex, by})

        {:lr, 0} ->
          {sy, ey} = if by > ay, do: {a.y + a.h, b.y}, else: {a.y, b.y + b.h}
          curve({ax, sy}, {ax, (sy + ey) / 2}, {bx, (sy + ey) / 2}, {bx, ey})

        # Back up the page: out of the far end of the node, round everything
        # between the two, and into the side of the one it goes back to. Square,
        # with rounded corners, so it reads as a return and crosses no node.
        {:td, _} ->
          between =
            for {id, box} <- boxes, ranks[id] in ranks[edge.to]..ranks[edge.from]//1, do: box

          out = (between |> Enum.map(&(&1.x + &1.w)) |> Enum.max()) + 40
          low = a.y + a.h + 26
          r = 12

          d =
            "M#{n(ax)} #{n(a.y + a.h)} V#{n(low - r)} Q#{n(ax)} #{n(low)} #{n(ax + r)} #{n(low)} " <>
              "H#{n(out - r)} Q#{n(out)} #{n(low)} #{n(out)} #{n(low - r)} " <>
              "V#{n(by + r)} Q#{n(out)} #{n(by)} #{n(out - r)} #{n(by)} H#{n(b.x + b.w)}"

          {d, {out, by}, {b.x + b.w, by}, {out, (low + by) / 2}}

        {:lr, _} ->
          between =
            for {id, box} <- boxes, ranks[id] in ranks[edge.to]..ranks[edge.from]//1, do: box

          out = (between |> Enum.map(&(&1.y + &1.h)) |> Enum.max()) + 40
          far = a.x + a.w + 26
          r = 12

          d =
            "M#{n(a.x + a.w)} #{n(ay)} H#{n(far - r)} Q#{n(far)} #{n(ay)} #{n(far)} #{n(ay + r)} " <>
              "V#{n(out - r)} Q#{n(far)} #{n(out)} #{n(far - r)} #{n(out)} " <>
              "H#{n(bx + r)} Q#{n(bx)} #{n(out)} #{n(bx)} #{n(out - r)} V#{n(b.y + b.h)}"

          {d, {bx, out}, {bx, b.y + b.h}, {(far + bx) / 2, out}}
      end

    class =
      case edge.kind do
        kind when kind in [:dotted, :dotted_line] -> "d-edge d-dashed"
        :thick -> "d-edge d-thick"
        _ -> "d-edge"
      end

    path = ~s(<path class="#{class}" d="#{d}"/>)
    arrow = if edge.kind in [:line, :dotted_line], do: "", else: head(tip, from)

    words =
      case edge.label do
        nil ->
          ""

        lines ->
          {mx, my} = at
          w = widest(lines, @small) + 12
          h = length(lines) * @line
          rect(mx - w / 2, my - h / 2, w, h, "d-mask") <> text(lines, mx, my, "d-edge-label")
      end

    path <> arrow <> words
  end

  # A cubic curve: its path, where its arrowhead comes from, its tip and its middle.
  defp curve({sx, sy} = s, {c1x, c1y}, {c2x, c2y} = c2, {ex, ey} = e) do
    d = "M#{n(sx)} #{n(sy)} C#{n(c1x)} #{n(c1y)} #{n(c2x)} #{n(c2y)} #{n(ex)} #{n(ey)}"
    middle = {(sx + 3 * c1x + 3 * c2x + ex) / 8, (sy + 3 * c1y + 3 * c2y + ey) / 8}
    {d, if(c2 == e, do: s, else: c2), e, middle}
  end

  # == sequence diagrams ======================================================

  @arrows [
    {"-->>", :dashed, :filled},
    {"->>", :solid, :filled},
    {"--)", :dashed, :open},
    {"-)", :solid, :open},
    {"--x", :dashed, :filled},
    {"-x", :solid, :filled},
    {"-->", :dashed, :none},
    {"->", :solid, :none}
  ]

  @frames ~w(loop opt alt par critical break)

  defp sequence(lines) do
    start = %{names: %{}, order: [], steps: [], depth: 0}
    seq = Enum.reduce(lines, start, &seq_line/2)
    if seq.depth != 0 or seq.order == [], do: throw(:bad)
    draw_sequence(%{seq | order: Enum.reverse(seq.order), steps: Enum.reverse(seq.steps)})
  end

  defp seq_line(line, seq) do
    [word | tail] = String.split(line, ~r/\s+/, parts: 2)
    rest = tail |> List.first() |> Kernel.||("") |> String.trim()

    cond do
      word in ~w(participant actor) ->
        case Regex.run(~r/^(\S+)(?:\s+as\s+(.+))?$/, rest) do
          [_, id] -> participant(seq, id, [id])
          [_, id, name] -> participant(seq, id, label(name))
          nil -> throw(:bad)
        end

      word in ~w(autonumber activate deactivate) ->
        seq

      word in @frames ->
        step(%{seq | depth: seq.depth + 1}, {:open, word, rest})

      word in ~w(else and) ->
        if seq.depth == 0, do: throw(:bad)
        step(seq, {:divide, rest})

      line == "end" ->
        if seq.depth == 0, do: throw(:bad)
        step(%{seq | depth: seq.depth - 1}, :close)

      word == "Note" ->
        seq_note(rest, seq)

      true ->
        seq_message(line, seq)
    end
  end

  defp participant(seq, id, name) do
    if Map.has_key?(seq.names, id),
      do: %{seq | names: Map.put(seq.names, id, name)},
      else: %{seq | names: Map.put(seq.names, id, name), order: [id | seq.order]}
  end

  defp step(seq, step), do: %{seq | steps: [step | seq.steps]}

  defp seq_note(rest, seq) do
    case Regex.run(~r/^(over|right of|left of)\s+([^:]+):\s*(.+)$/, rest) do
      [_, side, who, words] ->
        ids = who |> String.split(",") |> Enum.map(&String.trim/1)
        seq = Enum.reduce(ids, seq, &participant_once/2)
        side = %{"over" => :over, "right of" => :right, "left of" => :left}[side]
        step(seq, {:note, side, ids, label(words)})

      nil ->
        throw(:bad)
    end
  end

  defp seq_message(line, seq) do
    found =
      Enum.find_value(@arrows, fn {arrow, stroke, tip} ->
        case Regex.run(
               ~r/^([^\s:>-]+)\s*#{Regex.escape(arrow)}[+-]?\s*([^\s:]+)\s*(?::\s*(.*))?$/,
               line
             ) do
          [_, from, to | words] -> {from, to, stroke, tip, words |> List.first() |> Kernel.||("")}
          nil -> nil
        end
      end)

    {from, to, stroke, tip, words} = found || throw(:bad)
    seq = seq |> then(&participant_once(from, &1)) |> then(&participant_once(to, &1))
    step(seq, {:message, from, to, stroke, tip, if(words == "", do: [], else: label(words))})
  end

  defp participant_once(id, seq) do
    if Map.has_key?(seq.names, id), do: seq, else: participant(seq, id, [id])
  end

  # -- sequence layout and drawing ----------------------------------------------

  defp draw_sequence(seq) do
    column = seq.order |> Enum.with_index() |> Map.new()
    count = length(seq.order)
    box_w = Map.new(seq.order, fn id -> {id, max(84, widest(seq.names[id]) + 32)} end)
    box_h = 40 + ((seq.names |> Map.values() |> Enum.map(&length/1) |> Enum.max()) - 1) * @line

    # the gap between two neighbours: room for their boxes, and for the words
    # of every message that crosses it
    gaps =
      for i <- 0..max(count - 2, 0)//1, count > 1 do
        {a, b} = {Enum.at(seq.order, i), Enum.at(seq.order, i + 1)}
        base = max(120, (box_w[a] + box_w[b]) / 2 + 28)

        Enum.reduce(seq.steps, base, fn
          {:message, from, to, _, _, words}, gap when words != [] and from != to ->
            {lo, hi} = Enum.min_max([column[from], column[to]])

            if i >= lo and i < hi,
              do: max(gap, (widest(words, @small) + 28) / (hi - lo)),
              else: gap

          _, gap ->
            gap
        end)
      end

    first = box_w[hd(seq.order)] / 2 + @pad + 24

    xs =
      gaps
      |> Enum.scan(first, &(&2 + &1))
      |> then(&[first | &1])
      |> Enum.zip(seq.order)
      |> Map.new(fn {x, id} -> {id, x} end)

    last_x = xs[List.last(seq.order)]
    right = last_x + box_w[List.last(seq.order)] / 2
    top = @pad + box_h + 28

    {body, y, right, _} =
      Enum.reduce(seq.steps, {"", top, right, []}, fn step, {body, y, right, open} ->
        case step do
          {:message, id, id, stroke, tip, words} ->
            x = xs[id]
            class = if stroke == :dashed, do: "d-edge d-dashed", else: "d-edge"

            loop =
              ~s(<path class="#{class}" d="M#{n(x)} #{n(y)} H#{n(x + 36)} V#{n(y + 22)} H#{n(x)}"/>)

            tw = if words == [], do: 0, else: widest(words, @small)

            said =
              if words == [], do: "", else: text(words, x + 46 + tw / 2, y + 11, "d-edge-label")

            {body <> loop <> tip({x, y + 22}, {x + 36, y + 22}, tip) <> said, y + 50,
             max(right, x + 52 + tw), open}

          {:message, from, to, stroke, tip, words} ->
            {x1, x2} = {xs[from], xs[to]}
            lines = length(words)
            y = y + max(lines - 1, 0) * @line
            class = if stroke == :dashed, do: "d-edge d-dashed", else: "d-edge"
            line = ~s(<path class="#{class}" d="M#{n(x1)} #{n(y)} H#{n(x2)}"/>)

            said =
              if words == [],
                do: "",
                else: text(words, (x1 + x2) / 2, y - 11 - (lines - 1) * @line / 2, "d-edge-label")

            {body <> line <> tip({x2, y}, {x1, y}, tip) <> said, y + 44, right, open}

          {:note, side, ids, words} ->
            w = widest(words, @small) + 24
            h = length(words) * @line + 12
            {lo, hi} = ids |> Enum.map(&xs[&1]) |> Enum.min_max()

            x =
              case side do
                :over -> (lo + hi) / 2 - max(w, hi - lo + 32) / 2
                :right -> hi + 12
                :left -> lo - 12 - w
              end

            w = if side == :over, do: max(w, hi - lo + 32), else: w

            note =
              rect(x, y - 22, w, h, "d-note", 6) <>
                text(words, x + w / 2, y - 22 + h / 2, "d-edge-label")

            {body <> note, y + h + 14, max(right, x + w), open}

          {:open, kind, words} ->
            {body, y + 30, right, [{kind, words, y - 20, []} | open]}

          {:divide, words} ->
            [{kind, title, start, parts} | rest] = open
            {body, y + 26, right, [{kind, title, start, [{y - 16, words} | parts]} | rest]}

          :close ->
            [{kind, words, start, parts} | rest] = open
            inset = length(rest) * 8
            x = @pad + inset
            w = right + 16 - inset - x
            title = String.trim("#{kind} #{words}")

            frame =
              rect(x, start, w, y - 14 - start, "d-frame", 6) <>
                ~s(<text class="d-frame-label" x="#{n(x + 10)}" y="#{n(start + 13)}" dominant-baseline="central">#{escape(title)}</text>) <>
                Enum.map_join(parts, fn {at, said} ->
                  ~s(<path class="d-edge d-dashed" d="M#{n(x)} #{n(at)} H#{n(x + w)}"/>) <>
                    ~s(<text class="d-frame-label" x="#{n(x + 10)}" y="#{n(at + 12)}" dominant-baseline="central">#{escape(said)}</text>)
                end)

            {frame <> body, y + 6, right, rest}
        end
      end)

    bottom = y - 10

    heads =
      Enum.map_join(seq.order, fn id ->
        x = xs[id]

        ~s(<path class="d-life" d="M#{n(x)} #{n(@pad + box_h)} V#{n(bottom)}"/>) <>
          rect(x - box_w[id] / 2, @pad, box_w[id], box_h, "d-node", 6) <>
          text(seq.names[id], x, @pad + box_h / 2, "d-label")
      end)

    summary =
      "Sequence diagram: " <>
        (seq.steps
         |> Enum.flat_map(fn
           {:message, from, to, _, _, words} ->
             said = if words == [], do: "", else: ": #{Enum.join(words, " ")}"
             ["#{Enum.join(seq.names[from], " ")} to #{Enum.join(seq.names[to], " ")}#{said}"]

           _ ->
             []
         end)
         |> Enum.join("; "))

    {:ok, figure(heads <> body, right + 16 + @pad, bottom + @pad, summary)}
  end

  defp tip(_at, _from, :none), do: ""
  defp tip(at, from, :filled), do: head(at, from)
  defp tip(at, from, :open), do: head(at, from, true)
end
