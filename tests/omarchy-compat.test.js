// The theme against the Omarchy installed here: what an `omarchy-update` can
// break without any change in this repo. Run it after updating Omarchy.
// Skipped where Omarchy isn't installed (CI). Run with: node tests/omarchy-compat.test.js
const assert = require("assert")
const { spawnSync } = require("child_process")
const fs = require("fs")
const os = require("os")
const path = require("path")

const repo = path.join(__dirname, "..")
const omarchy = process.env.OMARCHY_PATH || "/usr/share/omarchy"
const plugins = path.join(omarchy, "shell/plugins")
if (!fs.existsSync(plugins)) {
  console.log(`omarchy compatibility: skipped (no Omarchy at ${omarchy})`)
  process.exit(0)
}
const run = (cmd, args, opts = {}) => spawnSync(cmd, args, { encoding: "utf8", ...opts })
const has = (cmd) => run("sh", ["-c", `command -v ${cmd}`]).status === 0
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "macos-theme-compat-"))

// Where Omarchy keeps a built-in plugin, as its catalog says, else its usual folder.
function source(id, fallback) {
  if (has("omarchy-plugin-catalog")) {
    const list = JSON.parse(run("omarchy-plugin-catalog", []).stdout || "[]")
    const found = list.find((p) => p.firstParty && p.id === id)
    if (found) return found.sourceDir
  }
  return path.join(plugins, fallback)
}

try {
  // The patches still take on this Omarchy's menu and workspaces: each leaves its mark.
  for (const [id, fallback, file, patch, mark] of [
    ["omarchy.menu", "menu", "Menu.qml", "menu-patch.pl", "macOS theme: wider"],
    ["omarchy.workspaces", "bar/widgets", "Workspaces.qml", "workspaces-patch.pl", "macOS theme: a click"],
  ]) {
    const copy = path.join(tmp, file)
    fs.copyFileSync(path.join(source(id, fallback), file), copy)
    const r = run("perl", ["-0pi", path.join(repo, patch), copy])
    assert.strictEqual(r.status, 0, r.stderr)
    assert.ok(fs.readFileSync(copy, "utf8").includes(mark), `${patch} no longer applies to this Omarchy's ${file}`)
  }

  // The lock: Omarchy's lock code drives the theme's LockView.qml, so every
  // property and handler it sets on LockView must exist in ours, or the lock
  // screen fails to load.
  const service = fs.readFileSync(path.join(source("omarchy.lock", "lock"), "Service.qml"), "utf8")
  const ours = fs.readFileSync(path.join(repo, "lock/LockView.qml"), "utf8")
  const declared = new Set([...ours.matchAll(/^\s*(?:required |readonly )*property \S+ (\w+)/gm)].map((m) => m[1]))
  const signals = new Set([...ours.matchAll(/^\s*signal (\w+)/gm)].map((m) => m[1]))
  const builtin = new Set(["id", "anchors", "visible", "color", "focus", "width", "height", "x", "y", "z", "opacity"])
  const used = new Set()
  for (const block of service.matchAll(/LockView \{([\s\S]*?)\n\s*\}/g))
    for (const name of block[1].matchAll(/^\s*([a-zA-Z]+)\s*:/gm)) used.add(name[1])
  assert.ok(used.size > 0, "Omarchy's lock no longer makes a LockView the way this test reads it")
  const handled = (name) => /^on[A-Z]/.test(name) && signals.has(name[2].toLowerCase() + name.slice(3))
  const missing = [...used].filter((name) => !builtin.has(name) && !declared.has(name) && !handled(name))
  assert.deepStrictEqual(missing, [], `Omarchy's lock sets these on LockView, which lock/LockView.qml lacks`)

  // Each of the theme's plugins is one this Omarchy accepts.
  if (has("omarchy")) {
    for (const dir of fs.readdirSync(path.join(repo, "plugins"))) {
      const r = run("omarchy", ["plugin", "validate", path.join(repo, "plugins", dir)])
      assert.strictEqual(r.status, 0, `${dir}: ${r.stdout}${r.stderr}`)
    }
  }

  // No QML file of the theme has a syntax error. Only syntax: the rest of
  // what qmllint says is about modules the running shell provides.
  const qmllint = ["/usr/lib/qt6/bin/qmllint", "qmllint6", "qmllint"].find((c) => has(c))
  if (qmllint) {
    const files = ["plugins", "lock", "workspaces"].flatMap((top) =>
      run("find", [path.join(repo, top), "-name", "*.qml"]).stdout.split("\n").filter(Boolean))
    const broken = files.flatMap((f) => run(qmllint, [f]).stderr.split("\n").filter((l) => l.includes("[syntax]")))
    assert.deepStrictEqual(broken, [])
  }
} finally {
  fs.rmSync(tmp, { recursive: true, force: true })
}

console.log("omarchy compatibility: ok")
