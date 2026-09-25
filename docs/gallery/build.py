#!/usr/bin/env python3
"""Builds the dart_not_native rendering galleries in docs/gallery/.

One CounterApp / one design-system screen, captured on all four renderers
(Flutter engine, Android Views, UIKit, browser DOM) and laid out side by side.

    python3 docs/gallery/build.py

Screenshots live in docs/gallery/images/ as <gallery>-<renderer>.png. Regenerate
them by running each example on a device and re-capturing (see each footer).
"""
import base64
import pathlib

DOCS = pathlib.Path(__file__).resolve().parent
IMG = DOCS / "images"

DOTS = {
    "flutter": "#7C6BD6",
    "android": "#3DDC84",
    "ios": "#0A84FF",
    "web": "#E4682B",
}


def img_src(file, mode):
    if mode == "embed":
        raw = (IMG / file).read_bytes()
        return "data:image/png;base64," + base64.b64encode(raw).decode()
    return f"images/{file}"


CSS = """
  :root {
    --bg: #f5f6f8; --panel: #ffffff; --ink: #15181e; --muted: #5a6473;
    --hair: #e4e7ec; --bezel: #d7dbe2; --bezel-bg: #eceef2;
    --accent: #4b5bd7; --add: #1f7a4d; --add-bg: #e8f6ee; --del: #9aa0ab;
    --shadow: 0 1px 2px rgba(16,20,30,.05), 0 12px 30px -12px rgba(16,20,30,.18);
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #0f1216; --panel: #171b21; --ink: #eaecef; --muted: #98a2b3;
      --hair: #262c35; --bezel: #2b323c; --bezel-bg: #10141a;
      --accent: #8a97ff; --add: #58c98d; --add-bg: #12241b; --del: #626b78;
      --shadow: 0 1px 2px rgba(0,0,0,.4), 0 16px 40px -16px rgba(0,0,0,.6);
    }
  }
  :root[data-theme="light"] {
    --bg: #f5f6f8; --panel: #ffffff; --ink: #15181e; --muted: #5a6473;
    --hair: #e4e7ec; --bezel: #d7dbe2; --bezel-bg: #eceef2;
    --accent: #4b5bd7; --add: #1f7a4d; --add-bg: #e8f6ee; --del: #9aa0ab;
    --shadow: 0 1px 2px rgba(16,20,30,.05), 0 12px 30px -12px rgba(16,20,30,.18);
  }
  :root[data-theme="dark"] {
    --bg: #0f1216; --panel: #171b21; --ink: #eaecef; --muted: #98a2b3;
    --hair: #262c35; --bezel: #2b323c; --bezel-bg: #10141a;
    --accent: #8a97ff; --add: #58c98d; --add-bg: #12241b; --del: #626b78;
    --shadow: 0 1px 2px rgba(0,0,0,.4), 0 16px 40px -16px rgba(0,0,0,.6);
  }

  * { box-sizing: border-box; }
  body {
    margin: 0; background: var(--bg); color: var(--ink);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    line-height: 1.5; -webkit-font-smoothing: antialiased;
  }
  a { color: var(--accent); }
  .mono { font-family: ui-monospace, "SF Mono", "SFMono-Regular", Menlo, Consolas, monospace; }
  .wrap { max-width: 1080px; margin: 0 auto; padding: clamp(24px, 5vw, 64px) clamp(18px, 4vw, 40px) 64px; }

  .eyebrow {
    font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
    font-size: 12.5px; letter-spacing: .08em; text-transform: uppercase;
    color: var(--muted); display: inline-flex; gap: .5ch; align-items: center;
  }
  .eyebrow b { color: var(--accent); font-weight: 600; }
  .back { text-decoration: none; }
  .back:hover { text-decoration: underline; }
  h1 {
    font-size: clamp(28px, 5.2vw, 50px); line-height: 1.05; letter-spacing: -.02em;
    text-wrap: balance; margin: 14px 0 0; font-weight: 680;
  }
  .lede { max-width: 60ch; color: var(--muted); font-size: clamp(16px, 1.6vw, 18px); margin: 16px 0 0; }
  .lede b { color: var(--ink); font-weight: 600; }

  .diff {
    margin: 28px 0 0; background: var(--panel); border: 1px solid var(--hair);
    border-radius: 14px; box-shadow: var(--shadow); overflow: hidden; max-width: 720px;
  }
  .diff pre { margin: 0; padding: 18px 20px; font-size: clamp(12px, 1.5vw, 14px); line-height: 1.9; overflow-x: auto; }
  .diff .row { display: block; white-space: pre; }
  .diff .del { color: var(--del); }
  .diff .add { color: var(--add); background: var(--add-bg); }
  .diff .sign { display: inline-block; width: 1.4ch; opacity: .8; }
  .diff .cmt { color: var(--muted); }
  .diff figcaption {
    display: block; border-top: 1px solid var(--hair); padding: 12px 20px;
    color: var(--muted); font-size: 13.5px; line-height: 1.6;
  }
  .diff figcaption .k { color: var(--accent); }
  .diff figcaption code { font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; }

  .chips { margin: 26px 0 0; display: flex; flex-wrap: wrap; gap: 8px; max-width: 720px; }
  .chips .chip {
    font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; font-size: 12.5px;
    padding: 5px 10px; border: 1px solid var(--hair); border-radius: 999px;
    background: var(--panel); color: var(--ink);
  }
  .chips-cap { margin: 12px 0 0; color: var(--muted); font-size: 13.5px; max-width: 62ch; }

  .gallery { margin: 40px 0 0; display: grid; grid-template-columns: repeat(4, 1fr); gap: clamp(14px, 2.4vw, 26px); }
  .tile { margin: 0; display: flex; flex-direction: column; gap: 14px; }
  .phone { background: var(--bezel-bg); border: 1px solid var(--bezel); border-radius: 20px; padding: 5px; box-shadow: var(--shadow); }
  .phone img { display: block; width: 100%; height: auto; border-radius: 15px; }
  figcaption { display: flex; flex-direction: column; gap: 5px; }
  .tile .name { display: inline-flex; align-items: center; gap: 8px; font-weight: 640; font-size: 15px; letter-spacing: -.01em; }
  .tile .sub { color: var(--muted); font-size: 13px; }
  .tile code { font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; font-size: 11.5px; color: var(--muted); margin-top: 1px; }
  .dot { width: 9px; height: 9px; border-radius: 50%; background: var(--dot); flex: 0 0 auto; box-shadow: 0 0 0 3px color-mix(in srgb, var(--dot) 20%, transparent); }

  .notice { margin: 52px 0 0; border-top: 1px solid var(--hair); padding-top: 34px; }
  .notice h2 { font-size: 14px; text-transform: uppercase; letter-spacing: .08em; color: var(--muted); margin: 0 0 20px; font-weight: 600; }
  .notice ul { list-style: none; margin: 0; padding: 0; display: grid; grid-template-columns: repeat(2, 1fr); gap: 18px 34px; }
  .notice li { display: flex; gap: 12px; align-items: flex-start; }
  .notice li .dot { margin-top: 7px; }
  .notice b { font-weight: 640; }
  .notice p { margin: 3px 0 0; color: var(--muted); font-size: 14.5px; }

  footer { margin: 52px 0 0; border-top: 1px solid var(--hair); padding-top: 26px; color: var(--muted); font-size: 13.5px; }
  footer .cap { display: grid; grid-template-columns: repeat(2, 1fr); gap: 8px 34px; max-width: 760px; }
  footer code { font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; font-size: 12px; color: var(--ink); }
  footer .tag { margin-top: 22px; color: var(--ink); font-weight: 600; }
  footer .tag span { color: var(--muted); font-weight: 400; }

  /* index */
  .cards { margin: 40px 0 0; display: grid; grid-template-columns: repeat(2, 1fr); gap: 22px; }
  .card { display: block; text-decoration: none; color: inherit; background: var(--panel); border: 1px solid var(--hair);
    border-radius: 16px; padding: 20px; box-shadow: var(--shadow); }
  .card h3 { margin: 0; font-size: 20px; letter-spacing: -.01em; }
  .card p { margin: 8px 0 0; color: var(--muted); font-size: 14.5px; }
  .card .strip { margin: 18px 0 0; display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; }
  .card .strip img { width: 100%; height: auto; border-radius: 8px; border: 1px solid var(--hair); background: var(--bezel-bg); }
  .card .go { margin: 16px 0 0; color: var(--accent); font-weight: 600; font-size: 14px; }
  .legend { margin: 34px 0 0; display: flex; flex-wrap: wrap; gap: 16px; color: var(--muted); font-size: 13.5px; }
  .legend span { display: inline-flex; align-items: center; gap: 7px; }

  @media (max-width: 860px) { .gallery { grid-template-columns: repeat(2, 1fr); } .cards { grid-template-columns: 1fr; } }
  @media (max-width: 620px) { .notice ul, footer .cap { grid-template-columns: 1fr; } }
  @media (prefers-reduced-motion: no-preference) { .phone, .card { transition: transform .25s ease; } .phone:hover, .card:hover { transform: translateY(-4px); } }
"""


def shell(title, body, favicon_note=""):
    return f"<title>{title}</title>\n<style>{CSS}</style>\n<div class=\"wrap\">\n{body}\n</div>\n"


def tiles_html(tiles, mode):
    out = []
    for t in tiles:
        out.append(f"""
      <figure class="tile">
        <div class="phone"><img src="{img_src(t['img'], mode)}" alt="{t['renderer']} rendering" loading="lazy" /></div>
        <figcaption>
          <span class="name"><span class="dot" style="--dot:{DOTS[t['key']]}"></span>{t['renderer']}</span>
          <span class="sub">{t['sub']}</span>
          <code>{t['ctrl']}</code>
        </figcaption>
      </figure>""")
    return "\n".join(out)


def notice_html(tiles):
    out = []
    for t in tiles:
        out.append(f"""
        <li>
          <span class="dot" style="--dot:{DOTS[t['key']]}"></span>
          <div><b>{t['renderer']}</b><p>{t['notice']}</p></div>
        </li>""")
    return "\n".join(out)


def render_gallery(cfg, mode):
    # In docs the eyebrow links back to the index; a standalone (embed) page has
    # no sibling index, so it is plain text there.
    if mode == "relative":
        crumb = '<a class="eyebrow back" href="index.html">&larr;&nbsp;<b>dart_not_native</b>&nbsp;rendering gallery</a>'
    else:
        crumb = '<span class="eyebrow"><b>dart_not_native</b>&nbsp;/&nbsp;rendering gallery</span>'
    body = f"""  <header>
    {crumb}
    <h1>{cfg['h1']}</h1>
    <p class="lede">{cfg['lede']}</p>
    {cfg['intro']}
  </header>

  <section class="gallery">{tiles_html(cfg['tiles'], mode)}
  </section>

  <section class="notice">
    <h2>Same code &mdash; what each renderer does differently</h2>
    <ul>{notice_html(cfg['tiles'])}
    </ul>
  </section>

  <footer>
    <div class="cap">{cfg['footer']}</div>
    <p class="tag">Dart, not native. <span>One codebase &mdash; native everywhere it runs.</span></p>
  </footer>"""
    return shell(cfg["title"], body)


DIFF = """<figure class="diff mono">
      <pre><span class="row del"><span class="sign">-</span>import 'package:flutter/material.dart';<span class="cmt">        // the Flutter engine</span></span><span class="row add"><span class="sign">+</span>import 'package:dart_not_native/widgets.dart';<span class="cmt">   // native views everywhere</span></span></pre>
      <figcaption>Swap the import &mdash; everything below it, <span class="k">the entire <code>CounterApp</code></span>, stays byte-for-byte identical.</figcaption>
    </figure>"""

COUNTER = {
    "title": "Counter — four renderers — dart_not_native",
    "h1": "One widget tree, four renderers",
    "lede": "A normal Flutter counter and this one differ by exactly <b>one line</b> &mdash; the import. That single swap lets the same <code class=\"mono\">build</code> method render through four different renderers, each drawing with the platform&rsquo;s own controls.",
    "intro": DIFF,
    "tiles": [
        {"key": "flutter", "img": "counter-flutter.png", "renderer": "Flutter engine", "sub": "Material 3 widgets", "ctrl": "Scaffold · ElevatedButton · FAB",
         "notice": "Surface-tinted app bar, fully-rounded pill buttons, and a squircle FAB &mdash; painted by Flutter&rsquo;s own Material&nbsp;3."},
        {"key": "android", "img": "counter-android.png", "renderer": "Android Views", "sub": "Native Android UI", "ctrl": "MaterialToolbar · MaterialButton",
         "notice": "A solid Material app bar, <b>UPPERCASE</b> button labels, and a circular teal FAB &mdash; real Android views."},
        {"key": "ios", "img": "counter-ios.png", "renderer": "UIKit", "sub": "Native iOS UI", "ctrl": "UINavigationBar · UIButton",
         "notice": "Regular-weight title, mixed-case labels, and the iOS status bar with the Dynamic Island &mdash; UIKit controls."},
        {"key": "web", "img": "counter-web.png", "renderer": "Browser DOM", "sub": "HTML + CSS", "ctrl": "&lt;header&gt; · &lt;button&gt;",
         "notice": "Content centered by flexbox and buttons raised with a CSS box-shadow &mdash; plain HTML elements, Material stylesheet."},
    ],
    "footer": """<div>Flutter &mdash; <code>runApp(CounterApp(), nativeViews: false)</code>, profile build on an Android emulator.</div>
      <div>Android Views &mdash; <code>main_native_android.dart</code>, captured with <code>adb screencap</code>.</div>
      <div>UIKit &mdash; <code>main_native_ios.dart</code> on an iPhone&nbsp;17&nbsp;Pro simulator.</div>
      <div>Browser DOM &mdash; <code>dart2js</code> build (Material kit) in headless Chrome; the same shot the Maestro web flows take.</div>""",
}

DS_CHIPS = """<div class="chips">
      <span class="chip">Alert</span><span class="chip">LinearProgressIndicator</span><span class="chip">CircularProgressIndicator</span><span class="chip">Checkbox</span><span class="chip">Radio</span><span class="chip">Switch</span><span class="chip">Divider</span>
    </div>
    <p class="chips-cap">Every control on this one screen is a single widget tree &mdash; each platform draws it with its own toolkit, from alert banners to the toggle switch.</p>"""

DS = {
    "title": "Design system — four renderers — dart_not_native",
    "h1": "One design system, four renderers",
    "lede": "The design-system showcase &mdash; alert banners, progress indicators, and form controls &mdash; is a plain Flutter screen. The <b>same page</b> renders through four renderers; each draws the checkbox, radios, and switch with its own platform&rsquo;s controls.",
    "intro": DS_CHIPS,
    "tiles": [
        {"key": "flutter", "img": "ds-flutter.png", "renderer": "Flutter engine", "sub": "Material 3 widgets", "ctrl": "Alert · Switch · Radio",
         "notice": "Color-bar alerts with an &times; dismiss, filled Material&nbsp;3 radios, a rounded pill switch, and rounded progress."},
        {"key": "android", "img": "ds-android.png", "renderer": "Android Views", "sub": "Native Android UI", "ctrl": "SwitchCompat · RadioButton",
         "notice": "Alerts get a full border and a raised <b>DISMISS</b> button; the switch, radios, and checkbox are Material views."},
        {"key": "ios", "img": "ds-ios.png", "renderer": "UIKit", "sub": "Native iOS UI", "ctrl": "UISwitch · UIActivityIndicator",
         "notice": "No dismiss buttons; the toggle is a UISwitch pill and the two spinners render as iOS activity indicators."},
        {"key": "web", "img": "ds-web.png", "renderer": "Browser DOM", "sub": "HTML + CSS", "ctrl": "&lt;input&gt; · CSS switch",
         "notice": "Alerts, spinners, and a real <code>&lt;input&gt;</code> checkbox and radio &mdash; styled HTML, with a CSS toggle switch."},
    ],
    "footer": """<div>Flutter &mdash; <code>runApp(…, nativeViews: false)</code>, profile build on an Android emulator.</div>
      <div>Android Views &mdash; native run, captured with <code>adb screencap</code>.</div>
      <div>UIKit &mdash; native run on an iPhone&nbsp;17&nbsp;Pro simulator.</div>
      <div>Browser DOM &mdash; <code>dart2js</code> build (Material kit) in headless Chrome.</div>""",
}


def render_index(mode):
    def strip(prefix):
        return "".join(
            f'<img src="{img_src(f"{prefix}-{k}.png", mode)}" alt="{k}" loading="lazy" />'
            for k in ("flutter", "android", "ios", "web")
        )

    legend = "".join(
        f'<span><span class="dot" style="--dot:{DOTS[k]}"></span>{name}</span>'
        for k, name in [("flutter", "Flutter engine"), ("android", "Android Views"), ("ios", "UIKit"), ("web", "Browser DOM")]
    )
    body = f"""  <header>
    <span class="eyebrow"><b>dart_not_native</b>&nbsp;/&nbsp;rendering gallery</span>
    <h1>Same code, native everywhere it runs</h1>
    <p class="lede">Every example is a plain Flutter app. Swap one import and the same widget tree renders through the platform&rsquo;s own views &mdash; Flutter&rsquo;s Material&nbsp;3, Android Views, iOS UIKit, or the browser DOM. These galleries capture one screen on all four.</p>
    {DIFF}
    <div class="legend">{legend}</div>
  </header>

  <section class="cards">
    <a class="card" href="counter.html">
      <h3>The counter</h3>
      <p>The smallest app &mdash; app bar, buttons, and a FAB &mdash; four ways.</p>
      <div class="strip">{strip('counter')}</div>
      <div class="go">Open gallery &rarr;</div>
    </a>
    <a class="card" href="design-system.html">
      <h3>The design system</h3>
      <p>Alerts, progress, and form controls &mdash; the richest divergence.</p>
      <div class="strip">{strip('ds')}</div>
      <div class="go">Open gallery &rarr;</div>
    </a>
  </section>

  <footer>
    <p class="tag">Dart, not native. <span>One codebase &mdash; native everywhere it runs.</span></p>
  </footer>"""
    return shell("Rendering gallery — dart_not_native", body)


(DOCS / "counter.html").write_text(render_gallery(COUNTER, "relative"))
(DOCS / "design-system.html").write_text(render_gallery(DS, "relative"))
(DOCS / "index.html").write_text(render_index("relative"))
print("wrote index.html, counter.html, design-system.html")
