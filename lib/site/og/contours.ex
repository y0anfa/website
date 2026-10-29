defmodule Site.OG.Contours do
  @moduledoc """
  Topographic contour lines for the share images, as SVG path data.

  A smooth height field is built from three octaves of value noise plus one
  hill, all drawn from a seed string (the entry's slug), so a given slug always
  gets the same map. Contours are found with marching squares, chained into
  polylines and smoothed with quadratic curves.

  The field uses only hashing and arithmetic, so the output is the same on every
  machine, with no random state.
  """

  # Lattice spacing in pixels and weight of each noise octave.
  @octaves [{360, 1.0}, {170, 0.5}, {80, 0.22}]
  @levels 11
  @major_every 4

  @type paths :: %{minor: String.t(), major: String.t()}

  @doc """
  Contour paths for a `width` by `height` canvas.

  `:minor` and `:major` hold the path data of the ordinary and of the index
  (every fourth) contours; either can be empty. Options: `:cell` is the grid
  step in pixels (default 12).
  """
  @spec paths(String.t(), pos_integer(), pos_integer(), keyword()) :: paths()
  def paths(seed, width, height, opts \\ []) do
    cell = Keyword.get(opts, :cell, 12)
    # One grid point past each edge, so the lines run off the canvas.
    columns = div(width + cell - 1, cell) + 1
    rows = div(height + cell - 1, cell) + 1

    field = height_field(seed, width, height, cell, columns, rows)
    {low, high} = Enum.min_max(Tuple.to_list(field))

    contours =
      for index <- 1..@levels do
        level = low + (high - low) * index / (@levels + 1)

        path =
          field
          |> segments(level, cell, columns, rows)
          |> chains()
          |> Enum.map_join(" ", &path_data/1)

        {index, path}
      end

    %{
      minor: join(for({i, p} <- contours, rem(i, @major_every) != 0, do: p)),
      major: join(for({i, p} <- contours, rem(i, @major_every) == 0, do: p))
    }
  end

  defp join(paths), do: paths |> Enum.reject(&(&1 == "")) |> Enum.join(" ")

  # -- height field ------------------------------------------------------------

  defp height_field(seed, width, height, cell, columns, rows) do
    reach_x = (columns - 1) * cell
    reach_y = (rows - 1) * cell

    lattices =
      Enum.with_index(@octaves, fn {spacing, weight}, octave ->
        {spacing, weight, lattice(seed, octave, reach_x, reach_y, spacing)}
      end)

    total = lattices |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    hill = hill(seed, width, height)

    for row <- 0..(rows - 1), column <- 0..(columns - 1) do
      x = column * cell
      y = row * cell

      noise =
        Enum.reduce(lattices, 0.0, fn {spacing, weight, lattice}, sum ->
          sum + weight * sample(lattice, x / spacing, y / spacing)
        end)

      noise / total + hill.(x, y)
    end
    |> List.to_tuple()
  end

  # Random values on a grid of points `spacing` pixels apart, from a hash of the
  # seed, the octave and the position.
  defp lattice(seed, octave, reach_x, reach_y, spacing) do
    for ix <- 0..(div(reach_x, spacing) + 1),
        iy <- 0..(div(reach_y, spacing) + 1),
        into: %{} do
      <<value::16, _::binary>> = :crypto.hash(:sha256, [seed, 0, octave, ix, 0, iy])
      {{ix, iy}, value / 65_535}
    end
  end

  # Bilinear interpolation of the lattice with a smoothstep fade.
  defp sample(lattice, fx, fy) do
    ix = trunc(fx)
    iy = trunc(fy)
    tx = smooth(fx - ix)
    ty = smooth(fy - iy)

    top = lerp(lattice[{ix, iy}], lattice[{ix + 1, iy}], tx)
    bottom = lerp(lattice[{ix, iy + 1}], lattice[{ix + 1, iy + 1}], tx)
    lerp(top, bottom, ty)
  end

  defp smooth(t), do: t * t * (3 - 2 * t)
  defp lerp(a, b, t), do: a + (b - a) * t

  # One round hill, so some contours close into rings. Its position and size come
  # from the seed; it sits on the right, away from the title.
  defp hill(seed, width, height) do
    <<a::16, b::16, c::16, _::binary>> = :crypto.hash(:sha256, [seed, "hill"])
    cx = width * (0.58 + 0.38 * a / 65_535)
    cy = height * (0.12 + 0.76 * b / 65_535)
    sigma = 150 + 110 * c / 65_535

    fn x, y ->
      distance = (x - cx) * (x - cx) + (y - cy) * (y - cy)
      0.9 * :math.exp(-distance / (2 * sigma * sigma))
    end
  end

  # -- marching squares ----------------------------------------------------------

  # Each crossing of the level sits on a grid edge: {:h, i, j} joins grid points
  # (i, j) and (i + 1, j); {:v, i, j} joins (i, j) and (i, j + 1). A segment joins
  # the two crossings of one cell. Returns [{{edge, point}, {edge, point}}].
  defp segments(field, level, cell, columns, rows) do
    value = fn i, j -> elem(field, j * columns + i) end

    for j <- 0..(rows - 2), i <- 0..(columns - 2), reduce: [] do
      acc ->
        a = value.(i, j)
        b = value.(i + 1, j)
        c = value.(i + 1, j + 1)
        d = value.(i, j + 1)

        code =
          bit(a, level, 8) + bit(b, level, 4) + bit(c, level, 2) + bit(d, level, 1)

        centre_high? = (a + b + c + d) / 4 >= level

        edges = %{
          top: {:h, i, j},
          bottom: {:h, i, j + 1},
          left: {:v, i, j},
          right: {:v, i + 1, j}
        }

        for {from, to} <- cell_segments(code, centre_high?), reduce: acc do
          acc ->
            [
              {crossing(edges[from], field, level, cell, columns),
               crossing(edges[to], field, level, cell, columns)}
              | acc
            ]
        end
    end
  end

  defp bit(value, level, weight), do: if(value >= level, do: weight, else: 0)

  # Corners: a top left (8), b top right (4), c bottom right (2), d bottom left (1).
  defp cell_segments(0, _), do: []
  defp cell_segments(15, _), do: []
  defp cell_segments(1, _), do: [{:left, :bottom}]
  defp cell_segments(2, _), do: [{:bottom, :right}]
  defp cell_segments(3, _), do: [{:left, :right}]
  defp cell_segments(4, _), do: [{:top, :right}]
  defp cell_segments(5, false), do: [{:top, :right}, {:left, :bottom}]
  defp cell_segments(5, true), do: [{:left, :top}, {:bottom, :right}]
  defp cell_segments(6, _), do: [{:top, :bottom}]
  defp cell_segments(7, _), do: [{:left, :top}]
  defp cell_segments(8, _), do: [{:left, :top}]
  defp cell_segments(9, _), do: [{:top, :bottom}]
  defp cell_segments(10, false), do: [{:left, :top}, {:bottom, :right}]
  defp cell_segments(10, true), do: [{:top, :right}, {:left, :bottom}]
  defp cell_segments(11, _), do: [{:top, :right}]
  defp cell_segments(12, _), do: [{:left, :right}]
  defp cell_segments(13, _), do: [{:bottom, :right}]
  defp cell_segments(14, _), do: [{:left, :bottom}]

  # {edge, {x, y}}: where the level crosses the edge, by linear interpolation.
  defp crossing({:h, i, j} = edge, field, level, cell, columns) do
    v0 = elem(field, j * columns + i)
    v1 = elem(field, j * columns + i + 1)
    {edge, {(i + (level - v0) / (v1 - v0)) * cell, j * cell}}
  end

  defp crossing({:v, i, j} = edge, field, level, cell, columns) do
    v0 = elem(field, j * columns + i)
    v1 = elem(field, (j + 1) * columns + i)
    {edge, {i * cell, (j + (level - v0) / (v1 - v0)) * cell}}
  end

  # -- polylines -------------------------------------------------------------------

  # Joins segments that share a crossing into polylines. Returns a list of
  # `{:open | :closed, [point]}`, in a fixed order.
  defp chains(segments) do
    points =
      for {{ka, pa}, {kb, pb}} <- segments, entry <- [{ka, pa}, {kb, pb}], into: %{}, do: entry

    neighbours =
      Enum.reduce(segments, %{}, fn {{ka, _}, {kb, _}}, map ->
        map
        |> Map.update(ka, [kb], &[kb | &1])
        |> Map.update(kb, [ka], &[ka | &1])
      end)

    keys = Enum.sort(Map.keys(neighbours))
    ends = Enum.filter(keys, &(length(neighbours[&1]) == 1))

    {open, seen} =
      Enum.reduce(ends, {[], MapSet.new()}, fn key, {lines, seen} ->
        if key in seen do
          {lines, seen}
        else
          line = walk(neighbours, key)
          {[{:open, line} | lines], MapSet.union(seen, MapSet.new(line))}
        end
      end)

    {closed, _seen} =
      Enum.reduce(keys, {[], seen}, fn key, {lines, seen} ->
        if key in seen do
          {lines, seen}
        else
          line = walk(neighbours, key)
          {[{:closed, line} | lines], MapSet.union(seen, MapSet.new(line))}
        end
      end)

    for {kind, keys} <- Enum.reverse(open) ++ Enum.reverse(closed) do
      {kind, Enum.map(keys, &points[&1])}
    end
  end

  # Follows the chain from `start` until it ends or comes back to where it began.
  defp walk(neighbours, start), do: walk(neighbours, start, nil, start, [start])

  defp walk(neighbours, key, previous, start, path) do
    case Enum.sort(neighbours[key]) -- List.wrap(previous) do
      [] ->
        Enum.reverse(path)

      [next | _] when next == start ->
        Enum.reverse(path)

      [next | _] ->
        walk(neighbours, next, key, start, [next | path])
    end
  end

  # -- path data -------------------------------------------------------------------

  defp path_data({_kind, [_single]}), do: ""

  defp path_data({:open, [first, second]}), do: "M#{pt(first)}L#{pt(second)}"

  defp path_data({:open, [first | rest] = points}) do
    middles = points |> Enum.chunk_every(2, 1, :discard) |> Enum.map(&mid/1)
    last = List.last(points)
    corners = Enum.slice(rest, 0, length(rest) - 1)

    curves =
      corners
      |> Enum.zip(tl(middles))
      |> Enum.map_join(fn {corner, middle} -> "Q#{pt(corner)} #{pt(middle)}" end)

    "M#{pt(first)}L#{pt(hd(middles))}#{curves}L#{pt(last)}"
  end

  defp path_data({:closed, [_, _] = points}), do: path_data({:open, points})

  defp path_data({:closed, points}) do
    pairs = Enum.zip(points, tl(points) ++ [hd(points)])
    middles = Enum.map(pairs, fn {a, b} -> mid([a, b]) end)
    # The curve starts at the middle of the first edge, then bends at each next corner.
    corners = tl(points) ++ [hd(points)]

    curves =
      corners
      |> Enum.zip(tl(middles) ++ [hd(middles)])
      |> Enum.map_join(fn {corner, middle} -> "Q#{pt(corner)} #{pt(middle)}" end)

    "M#{pt(hd(middles))}#{curves}Z"
  end

  defp mid([{x1, y1}, {x2, y2}]), do: {(x1 + x2) / 2, (y1 + y2) / 2}

  defp pt({x, y}), do: "#{num(x)} #{num(y)}"

  defp num(value), do: :erlang.float_to_binary(value * 1.0, decimals: 1)
end
