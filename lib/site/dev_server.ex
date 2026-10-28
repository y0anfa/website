# The dev server needs Bandit and Plug, which only exist in the :dev
# environment. In :prod and :test this file compiles to nothing.
if Code.ensure_loaded?(Plug.Conn) and Code.ensure_loaded?(Bandit) do
  defmodule Site.DevServer do
    @moduledoc """
    The `mix site.serve` implementation: serves `dist/` with Bandit, rebuilds when
    sources change (mtime polling every second, no file_system dependency).
    """

    @poll_ms 1_000

    @doc "Builds, serves and watches until the VM stops. Never returns."
    @spec run(keyword()) :: no_return()
    def run(opts) do
      {port, build_opts} = Keyword.pop(opts, :port, 4000)
      out = Keyword.get(build_opts, :out, "dist")

      build(build_opts)

      {:ok, _server} =
        Bandit.start_link(
          plug: {Site.DevServer.Plug, dir: out},
          port: port,
          ip: :loopback,
          startup_log: false
        )

      Mix.shell().info("site.serve: http://localhost:#{port}/ (watching, ctrl-c twice to stop)")

      content = Keyword.get(build_opts, :content, "content")
      watch(build_opts, snapshot(code_paths()), snapshot([content, "assets"]))
    end

    # -- watching -----------------------------------------------------------

    defp watch(build_opts, code, data) do
      Process.sleep(@poll_ms)

      content = Keyword.get(build_opts, :content, "content")
      new_code = snapshot(code_paths())
      new_data = snapshot([content, "assets"])

      cond do
        new_code != code ->
          Mix.shell().info("site.serve: code or templates changed, recompiling")
          recompile()
          build(build_opts)

        new_data != data ->
          Mix.shell().info("site.serve: content or assets changed, rebuilding")
          build(build_opts)

        true ->
          :ok
      end

      watch(build_opts, new_code, new_data)
    end

    defp code_paths, do: ["lib", "templates"]

    # Path and mtime of every file under the given directories.
    defp snapshot(dirs) do
      for dir <- dirs,
          path <- Path.wildcard(Path.join(dir, "**"), match_dot: true),
          {:ok, %File.Stat{type: :regular, mtime: mtime}} <- [File.stat(path, time: :posix)] do
        {path, mtime}
      end
      |> Enum.sort()
    end

    defp recompile do
      Enum.each(["compile", "compile.all", "compile.elixir"], &Mix.Task.reenable/1)
      Mix.Task.run("compile")
    rescue
      error -> Mix.shell().error("site.serve: compile failed: " <> Exception.message(error))
    catch
      :exit, reason -> Mix.shell().error("site.serve: compile failed: " <> inspect(reason))
    end

    defp build(opts) do
      %{files: files, out: out} = Site.Build.run(opts)
      Mix.shell().info("site.serve: built #{files} files into #{out}")
    rescue
      error in Site.Error ->
        Mix.shell().error(
          "site.serve: build failed, still serving the last good build\n" <>
            Exception.message(error)
        )

      error ->
        Mix.shell().error(
          "site.serve: build crashed, still serving the last good build\n" <>
            Exception.format(:error, error, __STACKTRACE__)
        )
    end
  end

  defmodule Site.DevServer.Plug do
    @moduledoc """
    Serves the build output the way Cloudflare Workers assets would: directory
    URLs resolve to `index.html`, a missing trailing slash redirects, misses get
    `404.html` with status 404, and every response carries the headers parsed from
    `dist/_headers`, so CSP violations show up locally exactly as in production.
    """

    @behaviour Plug

    import Plug.Conn

    @impl Plug
    def init(opts), do: Keyword.fetch!(opts, :dir) |> Path.expand()

    @impl Plug
    def call(%Plug.Conn{method: method} = conn, dir) when method in ["GET", "HEAD"] do
      rules = rules(dir)

      case resolve(dir, conn) do
        {:file, path} -> send_file_resp(conn, 200, path, rules)
        {:redirect, location} -> redirect(conn, location, rules)
        :not_found -> send_file_resp(conn, 404, Path.join(dir, "404.html"), rules)
      end
    end

    def call(conn, _dir) do
      conn |> put_resp_header("allow", "GET, HEAD") |> send_resp(405, "method not allowed")
    end

    defp resolve(dir, conn) do
      with {:ok, rel} <- safe_path(conn.path_info),
           target = Path.join(dir, rel) do
        cond do
          String.ends_with?(conn.request_path, "/") -> index(target)
          File.regular?(target) -> {:file, target}
          File.regular?(Path.join(target, "index.html")) -> {:redirect, add_slash(conn)}
          true -> :not_found
        end
      else
        :error -> :not_found
      end
    end

    defp index(target) do
      index = Path.join(target, "index.html")
      if File.regular?(index), do: {:file, index}, else: :not_found
    end

    defp safe_path(segments) do
      with {:ok, decoded} <- decode(segments),
           {:ok, rel} <- Path.safe_relative(Enum.join(decoded, "/")) do
        {:ok, rel}
      else
        _ -> :error
      end
    end

    defp decode(segments) do
      {:ok, Enum.map(segments, &URI.decode/1)}
    rescue
      ArgumentError -> :error
    end

    defp add_slash(conn) do
      conn.request_path <>
        "/" <> if(conn.query_string == "", do: "", else: "?" <> conn.query_string)
    end

    defp redirect(conn, location, rules) do
      conn
      |> put_rules(rules)
      |> put_resp_header("location", location)
      |> send_resp(307, "")
    end

    defp send_file_resp(conn, status, path, rules) do
      case File.read(path) do
        {:ok, body} ->
          conn
          |> put_rules(rules)
          |> put_resp_header("content-type", content_type(path))
          |> send_resp(status, body)

        {:error, _} ->
          conn |> put_rules(rules) |> send_resp(404, "not found (run mix site.build)")
      end
    end

    defp put_rules(conn, rules) do
      rules
      |> Site.Headers.for_path(conn.request_path)
      |> Enum.reduce(conn, fn {name, value}, conn ->
        put_resp_header(conn, String.downcase(name), value)
      end)
    end

    defp rules(dir) do
      case File.read(Path.join(dir, "_headers")) do
        {:ok, text} -> Site.Headers.parse(text)
        {:error, _} -> []
      end
    end

    defp content_type(path) do
      type = MIME.from_path(path)

      if String.starts_with?(type, "text/") or type in ["application/javascript", "image/svg+xml"] do
        type <> "; charset=utf-8"
      else
        type
      end
    end
  end
end
