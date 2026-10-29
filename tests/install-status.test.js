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
// `omarchy theme current` prints $THEME; every other omarchy call succeeds quietly.
fs.writeFileSync(path.join(bin, "omarchy"), '#!/bin/sh\n[ "$1 $2" = "theme current" ] && echo "$THEME"\nexit 0\n', { mode: 0o755 })

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

  // --add installs only what it names.
  assert.strictEqual(run("--add", "rows", "--add", "dock").status, 0)
  s = status()
  assert.strictEqual(s.features.rows, true)
  assert.strictEqual(s.features.dock, true)
  assert.strictEqual(s.features.theme, false)
  assert.ok(fs.existsSync(path.join(home, ".config/omarchy/plugins/macos-theme.dock/manifest.json")))

  // --remove takes out only that piece.
  assert.strictEqual(run("--remove", "rows").status, 0)
  s = status()
  assert.strictEqual(s.features.rows, false)
  assert.strictEqual(s.features.dock, true)
  assert.ok(!fs.readFileSync(path.join(home, ".config/gtk-4.0/gtk.css"), "utf8").includes("current/theme/gtk.css"))

  // The theme can't be removed while it is the current theme.
  fs.mkdirSync(path.join(home, ".config/omarchy/themes/macos"), { recursive: true })
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
