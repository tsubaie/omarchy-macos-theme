// install.sh --add, --remove and --status --json, in a throwaway home with a fake
// omarchy command. Run with: node tests/install-status.test.js
const assert = require("assert")
const { execFileSync, spawnSync } = require("child_process")
const fs = require("fs")
const os = require("os")
const path = require("path")

const script = path.join(__dirname, "..", "install.sh")
const home = fs.mkdtempSync(path.join(os.tmpdir(), "macos-theme-test-"))
const bin = path.join(home, "bin")
fs.mkdirSync(bin)
// `omarchy theme current` prints the theme last set (or $THEME), `theme list` knows two themes,
// `plugin clone` makes an empty clone of the menu or the lock, and every other omarchy call succeeds quietly.
fs.writeFileSync(path.join(bin, "omarchy"), `#!/bin/sh
[ "$1 $2" = "theme current" ] && { cat "$HOME/current" 2>/dev/null || echo "$THEME"; }
[ "$1 $2" = "theme list" ] && printf 'Macos\\nTokyo Night\\n'
[ "$1 $2" = "theme set" ] && echo "$3" > "$HOME/current"
if [ "$1 $2" = "plugin clone" ]; then
  dir="$XDG_CONFIG_HOME/omarchy/plugins/me.\${3#omarchy.}"
  mkdir -p "$dir" && touch "$dir/Menu.qml"
  printf '{ "omarchy": { "clonedFrom": "%s" } }' "$3" > "$dir/manifest.json"
  echo "Cloned $3 to $dir and switched"
fi
exit 0
`, { mode: 0o755 })

const env = { ...process.env, HOME: home, XDG_CONFIG_HOME: path.join(home, ".config"), PATH: `${bin}:${process.env.PATH}`, THEME: "Tokyo Night" }
const run = (...args) => spawnSync("bash", [script, ...args], { env, encoding: "utf8" })
const status = () => JSON.parse(execFileSync("bash", [script, "--status", "--json"], { env, encoding: "utf8" }))
const pieces = ["theme", "rows", "icons", "wide-menu", "dock", "switcher", "osd", "dictation-hud", "menubar", "bar-icons", "lock", "widgets"]

try {
  // A fresh home: nothing installed, and every piece is reported.
  let s = status()
  assert.deepStrictEqual(Object.keys(s.features), pieces)
  assert.ok(Object.values(s.features).every((on) => on === false))
  assert.strictEqual(s.active, false)
  assert.deepStrictEqual(s.settings, { glass: 0.7, "web-glass": 1, snapping: 1, blur: 10, magnification: 1.75, "dock-size": 48 })

  // --add installs only what it names.
  assert.strictEqual(run("--add", "rows", "--add", "dock").status, 0)
  s = status()
  assert.strictEqual(s.features.rows, true)
  assert.strictEqual(s.features.dock, true)
  assert.strictEqual(s.features.theme, false)
  assert.ok(fs.existsSync(path.join(home, ".config/omarchy/plugins/macos-theme.dock/manifest.json")))

  // The wide menu on a computer with no menu clone yet makes one (and says when it can't patch it).
  const menu = run("--add", "wide-menu")
  assert.strictEqual(menu.status, 0, menu.stderr)
  assert.match(menu.stderr, /Could not patch/)

  // The lock screen clones Omarchy's lock and draws it with the macOS view; removing it removes the clone.
  const lockDir = path.join(home, ".config/omarchy/plugins/me.lock")
  assert.strictEqual(run("--add", "lock").status, 0)
  assert.strictEqual(status().features.lock, true)
  assert.match(fs.readFileSync(path.join(lockDir, "LockView.qml"), "utf8"), /The macOS lock screen/)
  assert.strictEqual(run("--add", "lock").status, 0)
  assert.strictEqual(fs.readdirSync(path.dirname(lockDir)).filter((d) => d.endsWith(".lock")).length, 1)
  assert.strictEqual(run("--remove", "lock").status, 0)
  assert.strictEqual(status().features.lock, false)
  assert.ok(!fs.existsSync(lockDir))

  // --remove takes out only that piece.
  assert.strictEqual(run("--remove", "rows").status, 0)
  s = status()
  assert.strictEqual(s.features.rows, false)
  assert.strictEqual(s.features.dock, true)
  assert.ok(!fs.readFileSync(path.join(home, ".config/gtk-4.0/gtk.css"), "utf8").includes("current/theme/gtk.css"))

  // Installing the theme again keeps wallpapers of your own; removing it keeps it in a backup.
  const themeDir = path.join(home, ".config/omarchy/themes/macos")
  assert.strictEqual(run("--add", "theme").status, 0)
  fs.writeFileSync(path.join(themeDir, "backgrounds/mine.jpg"), "")
  assert.strictEqual(run("--add", "theme").status, 0)
  assert.ok(fs.existsSync(path.join(themeDir, "backgrounds/mine.jpg")))
  assert.ok(fs.existsSync(path.join(themeDir, "look.lua")))

  // Settings: glass goes into look.lua and stays through a reinstall; magnification
  // goes into the dock's section of shell.json, next to what was there.
  const shellJson = path.join(home, ".config/omarchy/shell.json")
  fs.writeFileSync(shellJson, JSON.stringify({ dock: { position: "left" } }))
  assert.strictEqual(run("--set", "glass=0.85", "--set", "web-glass=0.9", "--set", "snapping=0", "--set", "blur=15", "--set", "magnification=1.2", "--set", "dock-size=60").status, 0)
  assert.deepStrictEqual(status().settings, { glass: 0.85, "web-glass": 0.9, snapping: 0, blur: 15, magnification: 1.2, "dock-size": 60 })
  const look = fs.readFileSync(path.join(themeDir, "look.lua"), "utf8")
  assert.match(look, /o\.window\("\.\*", \{ opacity = "0\.85 0\.85" \}\)/)
  assert.match(look, /brave-browser\|.*", \{ opacity = "0\.9 0\.9" \}\)/)
  assert.match(look, /^local SNAPPING = 0$/m)
  assert.match(look, /^local BLUR = 15$/m)
  assert.strictEqual(JSON.parse(fs.readFileSync(shellJson, "utf8")).dock.position, "left")
  assert.strictEqual(run("--add", "theme").status, 0)
  assert.deepStrictEqual(status().settings, { glass: 0.85, "web-glass": 0.9, snapping: 0, blur: 15, magnification: 1.2, "dock-size": 60 })
  for (const bad of ["glass=0.2", "glass=2", "magnification=3", "magnification=", "size=1", "glass=1.2.3", "snapping=0.5", "snapping=2", "blur=0.5", "blur=21", "blur=-1", "web-glass=0.1", "dock-size=31", "dock-size=81", "dock-size=50.5"]) {
    assert.strictEqual(run("--set", bad).status, 1, bad)
  }
  // A preview writes the settings as --set does, for a slider being dragged;
  // the same checks apply, and only settings that can be shown at once.
  // Blur and the dock's settings are shown in place, not written, so the
  // settings stay until Apply.
  assert.strictEqual(run("--preview", "--set", "blur=12", "--set", "dock-size=40").status, 0)
  assert.strictEqual(status().settings.blur, 15)
  assert.strictEqual(status().settings["dock-size"], 60)
  assert.strictEqual(run("--preview", "--set", "blur=21").status, 1)
  assert.strictEqual(run("--preview", "--set", "clock=left").status, 1)
  assert.strictEqual(run("--set", "blur=15", "--set", "dock-size=60").status, 0)
  const removed = run("--remove", "theme")
  assert.strictEqual(removed.status, 0, removed.stdout + removed.stderr)
  assert.strictEqual(status().features.theme, false)
  const kept = fs.readdirSync(path.join(home, ".config/omarchy/macos-theme-backups"))
  assert.ok(kept.some((d) => fs.existsSync(path.join(home, ".config/omarchy/macos-theme-backups", d, "backgrounds/mine.jpg"))))

  // The theme can't be removed while it is the current theme.
  fs.mkdirSync(themeDir, { recursive: true })
  fs.rmSync(path.join(home, "current"), { force: true })
  env.THEME = "Macos"
  s = status()
  assert.strictEqual(s.active, true)
  assert.strictEqual(s.features.theme, true)
  const refused = run("--remove", "theme")
  assert.strictEqual(refused.status, 1)
  assert.match(refused.stderr, /Switch to another theme first/)
  assert.strictEqual(status().features.theme, true)

  // Removing all of it while it is current switches to the theme named first, one that exists.
  assert.strictEqual(run("--switch-to", "Nope", "--uninstall").status, 1)
  assert.strictEqual(status().features.theme, true)
  const all = run("--switch-to", "Tokyo Night", "--uninstall", "--remove", "icons")
  assert.strictEqual(all.status, 0, all.stderr)
  s = status()
  assert.strictEqual(s.active, false)
  assert.ok(Object.values(s.features).every((on) => on === false))
  assert.strictEqual(fs.readFileSync(path.join(home, "current"), "utf8").trim(), "Tokyo Night")

  // The clock: where shell.json has it, right by default; only three places are taken.
  assert.strictEqual(status().clock, "right")
  fs.writeFileSync(path.join(home, ".config/omarchy/shell.json"), JSON.stringify({ bar: { layout: { left: [{ id: "omarchy.workspaces" }], centerEnd: [{ id: "omarchy.clock" }], right: [] } } }))
  assert.strictEqual(status().clock, "center")
  fs.writeFileSync(path.join(home, ".config/omarchy/shell.json"), JSON.stringify({ bar: { layout: { left: [{ id: "omarchy.clock" }] } } }))
  assert.strictEqual(status().clock, "left")
  assert.strictEqual(run("--set", "clock=center").status, 0)
  for (const bad of ["clock=top", "clock=", "clock=Left"]) assert.strictEqual(run("--set", bad).status, 1, bad)

  // The panels: bottom unless shell.json says top, each on its own, the rest of shell.json kept.
  assert.strictEqual(status()["volume-hud"], "bottom")
  assert.strictEqual(run("--set", "volume-hud=top").status, 0)
  s = status()
  assert.strictEqual(s["volume-hud"], "top")
  assert.strictEqual(s["dictation-hud"], "bottom")
  assert.deepStrictEqual(JSON.parse(fs.readFileSync(path.join(home, ".config/omarchy/shell.json"), "utf8")).bar.layout.left[0], { id: "omarchy.clock" })
  for (const bad of ["volume-hud=middle", "dictation-hud=", "hud=top"]) assert.strictEqual(run("--set", bad).status, 1, bad)

  // Desktop widgets: all of them while shell.json lays none out; --show-widgets
  // keeps the named ones where they sit, adds the rest without a cell, and
  // leaves the rest of shell.json alone.
  assert.deepStrictEqual(status().widgets, ["clock", "calendar", "weather", "playing"])
  fs.writeFileSync(shellJson, JSON.stringify({ dock: { magnification: 1.5 }, widgets: { screen: "DP-1", layout: [{ id: "weather", col: 2, row: 1 }, { id: "nope", col: 0, row: 0 }] } }))
  assert.deepStrictEqual(status().widgets, ["weather"])
  const shown = run("--show-widgets", "playing,weather")
  assert.strictEqual(shown.status, 0, shown.stderr)
  const saved = JSON.parse(fs.readFileSync(shellJson, "utf8"))
  assert.deepStrictEqual(saved.widgets, { screen: "DP-1", layout: [{ id: "weather", col: 2, row: 1 }, { id: "playing" }] })
  assert.strictEqual(saved.dock.magnification, 1.5)
  assert.deepStrictEqual(status().widgets, ["weather", "playing"])
  for (const bad of ["", ",", "clock,dock", "clock;rm"]) assert.strictEqual(run("--show-widgets", bad).status, 1, bad)
  fs.rmSync(shellJson)
  assert.strictEqual(run("--show-widgets", "calendar").status, 0)
  assert.deepStrictEqual(status().widgets, ["calendar"])

  // Unknown pieces are refused.
  assert.strictEqual(run("--remove", "everything").status, 1)
  assert.strictEqual(run("--add").status, 1)
} finally {
  fs.rmSync(home, { recursive: true, force: true })
}

console.log("install.sh --status --json: ok")
