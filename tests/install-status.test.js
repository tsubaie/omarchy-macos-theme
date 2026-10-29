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
// `omarchy theme current` prints $THEME, `plugin clone` makes an empty menu clone, and every
// other omarchy call succeeds quietly.
fs.writeFileSync(path.join(bin, "omarchy"), `#!/bin/sh
[ "$1 $2" = "theme current" ] && echo "$THEME"
if [ "$1 $2" = "plugin clone" ]; then
  mkdir -p "$XDG_CONFIG_HOME/omarchy/plugins/me.menu" && touch "$XDG_CONFIG_HOME/omarchy/plugins/me.menu/Menu.qml"
  echo "Cloned omarchy.menu to $XDG_CONFIG_HOME/omarchy/plugins/me.menu and switched"
fi
exit 0
`, { mode: 0o755 })

const env = { ...process.env, HOME: home, XDG_CONFIG_HOME: path.join(home, ".config"), PATH: `${bin}:${process.env.PATH}`, THEME: "Tokyo Night" }
const run = (...args) => spawnSync("bash", [script, ...args], { env, encoding: "utf8" })
const status = () => JSON.parse(execFileSync("bash", [script, "--status", "--json"], { env, encoding: "utf8" }))
const pieces = ["theme", "rows", "icons", "wide-menu", "dock", "switcher", "osd", "dictation-hud", "menubar"]

try {
  // A fresh home: nothing installed, and every piece is reported.
  let s = status()
  assert.deepStrictEqual(Object.keys(s.features), pieces)
  assert.ok(Object.values(s.features).every((on) => on === false))
  assert.strictEqual(s.active, false)
  assert.deepStrictEqual(s.settings, { glass: 0.7, magnification: 1.75 })

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
  assert.strictEqual(run("--set", "glass=0.85", "--set", "magnification=1.2").status, 0)
  assert.deepStrictEqual(status().settings, { glass: 0.85, magnification: 1.2 })
  assert.match(fs.readFileSync(path.join(themeDir, "look.lua"), "utf8"), /o\.window\("\.\*", \{ opacity = "0\.85 0\.85" \}\)/)
  assert.strictEqual(JSON.parse(fs.readFileSync(shellJson, "utf8")).dock.position, "left")
  assert.strictEqual(run("--add", "theme").status, 0)
  assert.strictEqual(status().settings.glass, 0.85)
  for (const bad of ["glass=0.2", "glass=2", "magnification=3", "magnification=", "size=1", "glass=1.2.3"]) {
    assert.strictEqual(run("--set", bad).status, 1, bad)
  }
  const removed = run("--remove", "theme")
  assert.strictEqual(removed.status, 0, removed.stdout + removed.stderr)
  assert.strictEqual(status().features.theme, false)
  const kept = fs.readdirSync(path.join(home, ".config/omarchy/macos-theme-backups"))
  assert.ok(kept.some((d) => fs.existsSync(path.join(home, ".config/omarchy/macos-theme-backups", d, "backgrounds/mine.jpg"))))

  // The theme can't be removed while it is the current theme.
  fs.mkdirSync(themeDir, { recursive: true })
  env.THEME = "Macos"
  s = status()
  assert.strictEqual(s.active, true)
  assert.strictEqual(s.features.theme, true)
  const refused = run("--remove", "theme")
  assert.strictEqual(refused.status, 1)
  assert.match(refused.stderr, /Switch to another theme first/)
  assert.strictEqual(status().features.theme, true)

  // Unknown pieces are refused.
  assert.strictEqual(run("--remove", "everything").status, 1)
  assert.strictEqual(run("--add").status, 1)
} finally {
  fs.rmSync(home, { recursive: true, force: true })
}

console.log("install.sh --status --json: ok")
