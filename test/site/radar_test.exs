defmodule Site.RadarTest do
  @moduledoc """
  The scope (SPEC section 7, The scope): `radar.js`, loaded on the home only, its
  canvas in `site.css`, and the game itself, run under node against stubs.
  """

  use ExUnit.Case, async: true

  import Site.TestHelpers

  @css File.read!("assets/css/site.css")
  @code Regex.replace(~r{/\*.*?\*/}s, @css, "")
  @script File.read!("assets/js/radar.js")
  @node System.find_executable("node")

  setup_all do
    r = if @node, do: run_node(harness(), "assets/js/radar.js")
    %{tree: build_fixtures() |> read_tree(), r: r}
  end

  describe "the page" do
    test "only the home loads radar.js, deferred, after favicon.js", %{tree: tree} do
      assert tree["index.html"] =~
               ~s(<script defer src="/assets/js/favicon.js"></script>\n) <>
                 ~s(<script defer src="/assets/js/radar.js"></script>\n)

      for {path, html} <- tree, String.ends_with?(path, ".html"), path != "index.html" do
        refute html =~ "radar.js", path
      end

      assert tree["assets/js/radar.js"] == @script
    end

    test "nothing in the markup gives it away", %{tree: tree} do
      refute tree["index.html"] =~ "<canvas"
      refute tree["index.html"] =~ ~r/class="[^"]*radar/
    end

    test "the script writes no inline style attribute and loads nothing" do
      refute @script =~ "setAttribute('style'"
      refute @script =~ "cssText"
      refute @script =~ "innerHTML"
      refute @script =~ ~r/fetch\(|XMLHttpRequest|import\(/
      refute @script =~ ~r{https?://}
    end
  end

  describe "site.css" do
    test "the canvas covers the window and takes the pointer only while the scope is open" do
      assert @code =~
               ~r/\.radar \{\s*position: fixed;\s*z-index: 30;\s*inset: 0;\s*width: 100%;\s*height: 100%;\s*pointer-events: none;\s*\}/

      assert @code =~
               ~r/\.radar-on \.radar \{\s*cursor: crosshair;\s*pointer-events: auto;\s*touch-action: none;\s*\}/
    end

    test "the page under the scope is dimmed almost away, and comes back" do
      assert @code =~
               ~r/\.stage,\s*\.corner,\s*\.line \{\s*transition: opacity 400ms var\(--ease\);\s*\}/

      assert @code =~ ~r/\.radar-on :is\(\.stage, \.corner, \.line\) \{\s*opacity: 0\.05;\s*\}/
    end
  end

  describe "radar.js under node" do
    if @node do
      test "holding the name's mark opens the scope; a press, or a hold let go, does not",
           %{r: r} do
        assert r["hold"]["error"] == nil
        assert r["hold"]["mounted"] == 1
        assert r["hold"]["on"] == true
        assert r["hold"]["inert"] == true

        for name <- ~w(press moved elsewhere other-button reduced) do
          assert r[name]["on"] == false, name
          assert r[name]["canvas"] == false, name
        end

        # a plain press does mount the canvas for a moment, and takes it away again
        assert r["press"]["mounted"] == 1
        assert r["elsewhere"]["mounted"] == 0
        assert r["reduced"]["mounted"] == 0
      end

      test "the canvas is drawn in the page's resolved colours, never in a custom property",
           %{r: r} do
        assert r["hold"]["probed"] == ~w[var(--text) var(--text-2) var(--text-3) var(--hair)]
        assert r["hold"]["colours"] == ["rgb(1, 2, 3)"]
        assert r["hold"]["hidden"] == "true"
      end

      test "a pulse takes out a contact where it really is, not where its echo is", %{r: r} do
        assert r["hit"]["score"] == "1"
        assert r["miss-on-echo"]["score"] == "0"
        # one pulse at a time
        assert r["reload"]["score"] == "1"
      end

      test "three contacts through, and the scope folds back; the page is itself again",
           %{r: r} do
        o = r["over"]
        assert o["canvas"] == false
        assert o["on"] == false
        assert o["inert"] == false
        assert o["removed"] == 1
        # about nineteen seconds of play, left alone
        assert o["seconds"] > 15 and o["seconds"] < 26
        assert o["stored"] == nil
      end

      test "a best score is kept, and shown beside the count next time", %{r: r} do
        assert r["best"]["stored"] == "1"
        assert r["best-shown"]["texts"] == ["0", "7"]
      end

      test "Escape folds the scope at once", %{r: r} do
        assert r["escape"]["prevented"] == true
        assert r["escape"]["canvas"] == false
        assert r["escape"]["on"] == false
        assert r["escape-idle"]["prevented"] == false
      end
    end
  end

  defp run_node(harness, script) do
    dir = tmp_dir("radar-node")
    path = Path.join(dir, "harness.cjs")
    File.write!(path, harness)

    case System.cmd(@node, [path, Path.expand(script)], stderr_to_stdout: true) do
      {out, 0} -> JSON.decode!(out)
      {out, status} -> flunk("node exited with #{status}:\n#{out}")
    end
  end

  # Runs radar.js against stubs: a 1000x800 window, the name's mark at (196.5, 114.5),
  # a canvas whose context records what is written, frames the test steps by hand,
  # and a Math.random that always answers 0, so every contact comes from the east
  # (angle 0) at 0.07 radii a second. The scope is then at (500, 400), radius 364.
  defp harness do
    ~S"""
    const fs = require('fs');
    const vm = require('vm');
    const src = fs.readFileSync(process.argv[2], 'utf8');

    function page(o = {}) {
      const doc = {}, win = {};
      const classes = new Set();
      const store = o.stored ? { radar: o.stored } : {};
      const s = { mounted: 0, removed: 0, texts: [], probed: [], colours: new Set(), frame: null, canvas: null, error: null };
      const inert = { stage: false };
      const stage = { set inert(v) { inert.stage = v; }, get inert() { return inert.stage; } };
      const name = { getBoundingClientRect: () => ({ left: 100, top: 100 }), style: { getPropertyValue: () => '' } };
      const body = {
        appendChild(c) { c.parentNode = body; s.mounted++; s.canvas = c; },
        removeChild(c) { c.parentNode = null; s.removed++; s.canvas = null; },
      };
      const context = new Proxy({}, {
        get: (t, k) => (k === 'measureText' ? () => ({ width: 8 }) : k === 'fillText' ? (text) => { s.texts.push(text); } : k in t ? t[k] : () => {}),
        set: (t, k, v) => { if (k === 'fillStyle' || k === 'strokeStyle') s.colours.add(v); t[k] = v; return true; },
      });
      const canvas = () => {
        const c = { listeners: {}, attrs: {}, parentNode: null };
        c.getContext = () => context;
        c.setAttribute = (k, v) => { c.attrs[k] = v; };
        c.addEventListener = (t, f) => { c.listeners[t] = f; };
        c.style = { setProperty: (k, v) => { s.probed.push(v); }, removeProperty() {} };
        return c;
      };
      const ctx = {
        Math: Object.assign(Object.create(Math), { random: () => 0 }),
        innerWidth: 1000, innerHeight: 800, devicePixelRatio: 2,
        document: {
          documentElement: { classList: { add: (c) => classes.add(c), remove: (...c) => c.forEach((x) => classes.delete(x)) } },
          body,
          querySelector: (sel) => (sel === '.identity' ? name : sel === '.stage' ? stage : null),
          createElement: canvas,
          addEventListener: (t, f) => { (doc[t] = doc[t] || []).push(f); },
        },
        matchMedia: () => ({ matches: !!o.reduced }),
        getComputedStyle: (el, pseudo) => (pseudo ? { top: '11px', height: '7px' } : { getPropertyValue: () => '96px', color: 'rgb(1, 2, 3)', fontFamily: 'Inter' }),
        requestAnimationFrame: (f) => { s.frame = f; return 1; },
        cancelAnimationFrame: () => { s.frame = null; },
        addEventListener: (t, f) => { (win[t] = win[t] || []).push(f); },
        localStorage: { getItem: (k) => (k in store ? store[k] : null), setItem: (k, v) => { store[k] = v; } },
      };
      ctx.window = ctx;
      try { vm.runInNewContext(src, ctx); } catch (e) { s.error = String(e); }

      let now = 0;
      const fire = (t, ev) => { for (const f of doc[t] || []) f(ev); };
      const at = (x, y, extra = {}) => ({ clientX: x, clientY: y, button: 0, isPrimary: true, timeStamp: now, stopPropagation() {}, ...extra });
      // step the clock, one 50ms frame at a time
      const run = (ms) => { for (const end = now + ms; now < end && s.frame; ) { now += 50; const f = s.frame; s.frame = null; f(now); } };
      const state = () => ({
        error: s.error, mounted: s.mounted, removed: s.removed, canvas: !!s.canvas, on: classes.has('radar-on'), inert: inert.stage,
        score: s.texts.length ? s.texts[s.texts.length - 1] : null, stored: store.radar === undefined ? null : store.radar,
      });
      return {
        s, state, run, fire,
        down: (x = 196, y = 115, extra) => fire('pointerdown', at(x, y, extra)),
        up: () => fire('pointerup', at(196, 115)),
        move: (x, y) => fire('pointermove', at(x, y)),
        // a press on the open scope
        pulse: (x, y) => s.canvas.listeners.pointerdown(at(x, y)),
        open: function () { this.down(); run(2100); },
        key: (key) => { let prevented = false; fire('keydown', { key, timeStamp: now, preventDefault() { prevented = true; } }); return prevented; },
        clock: () => now,
      };
    }

    const out = {};

    // ---- the hold
    { const p = page(); p.open(); out['hold'] = { ...p.state(), probed: p.s.probed, colours: [...p.s.colours], hidden: p.s.canvas.attrs['aria-hidden'] }; }
    { const p = page(); p.down(); p.run(600); p.up(); p.run(2000); out['press'] = p.state(); }
    { const p = page(); p.down(); p.run(600); p.move(260, 115); p.run(2000); out['moved'] = p.state(); }
    { const p = page(); p.down(400, 300); p.run(2100); out['elsewhere'] = p.state(); }
    { const p = page(); p.down(196, 115, { button: 2 }); p.run(2100); out['other-button'] = p.state(); }
    { const p = page({ reduced: true }); p.down(); p.run(2100); out['reduced'] = p.state(); }

    // ---- the game. The scope plays from 2050ms; the first contact leaves the rim
    // (864, 400) 900ms later and has come 0.07 * 364px inward for every second since.
    // The beam passes east, and paints its echo, 650ms after it sets out.
    const where = (seconds) => 500 + 364 * (1 - 0.07 * seconds);
    { const p = page(); p.open(); p.run(900 + 2000); p.pulse(where(2), 400); p.run(100); out['hit'] = p.state(); }
    { const p = page(); p.open(); p.run(900 + 2400); p.pulse(where(0.65), 300); p.run(100); out['miss-on-echo'] = p.state(); }
    {
      const p = page(); p.open(); p.run(900 + 2300 + 2000);
      // two contacts by now; the second pulse leaves too soon after the first
      p.pulse(where(4.3), 400); p.run(100); p.pulse(where(2.1), 400); p.run(100);
      out['reload'] = p.state();
    }

    // ---- left alone: three contacts through, then the scope folds
    { const p = page(); p.open(); const t0 = p.clock(); p.run(60000); out['over'] = { ...p.state(), seconds: (p.clock() - t0) / 1000 }; }
    { const p = page(); p.open(); p.run(900 + 2000); p.pulse(where(2), 400); p.run(60000); out['best'] = p.state(); }
    { const p = page({ stored: '7' }); p.open(); p.s.texts.length = 0; p.run(50); out['best-shown'] = { texts: p.s.texts.slice(0, 2) }; }

    // ---- Escape
    { const p = page(); p.open(); const prevented = p.key('Escape'); p.run(1000); out['escape'] = { ...p.state(), prevented }; }
    { const p = page(); out['escape-idle'] = { prevented: p.key('Escape') }; }

    console.log(JSON.stringify(out));
    """
  end
end
