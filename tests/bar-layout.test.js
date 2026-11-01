// install.sh --bar and --bar-layout, with a fake omarchy that knows a few bar
// widgets and records what it is asked to do. Run with: node tests/bar-layout.test.js
const assert = require("assert")
const { spawnSync } = require("child_process")
const fs = require("fs")
const os = require("os")
const path = require("path")

const script = path.join(__dirname, "..", "install.sh")
const home = fs.mkdtempSync(path.join(os.tmpdir(), "macos-theme-bar-"))
const bin = path.join(home, "bin")
fs.mkdirSync(bin)
const plugins = [
  { id: "omarchy.clock", name: "Clock", kinds: ["bar-widget"], enabled: true, clonedFrom: "" },
  { id: "omarchy.weather", name: "Weather", kinds: ["bar-widget"], enabled: true, clonedFrom: "" },
  { id: "omarchy.media", name: "Media", kinds: ["bar-widget"], enabled: false, clonedFrom: "" },
  { id: "omarchy.tray", name: "System tray", kinds: ["bar-widget"], enabled: false, clonedFrom: "" },
  { id: "me.tray", name: "My tray", kinds: ["bar-widget"], enabled: true, clonedFrom: "omarchy.tray" },
  { id: "omarchy.dock", name: "Dock", kinds: ["service"], enabled: true, clonedFrom: "" },
]
fs.writeFileSync(path.join(home, "plugins.json"), JSON.stringify(plugins))
fs.writeFileSync(path.join(bin, "omarchy"), `#!/bin/sh
[ "$1 $2" = "theme current" ] && { echo "Tokyo Night"; exit 0; }
if [ "$1 $2 $3" = "plugin list --json" ]; then cat "$HOME/plugins.json"; exit 0; fi
echo "$*" >> "$HOME/calls"
exit 0
`, { mode: 0o755 })
fs.mkdirSync(path.join(home, ".config/omarchy"), { recursive: true })
fs.writeFileSync(path.join(home, ".config/omarchy/shell.json"), JSON.stringify({
  bar: { layout: { left: [{ id: "me.tray" }], right: [{ id: "omarchy.weather" }, { id: "omarchy.clock" }] } },
}))
const env = { ...process.env, HOME: home, XDG_CONFIG_HOME: path.join(home, ".config"), PATH: `${bin}:${process.env.PATH}`, MACOS_THEME_NO_SNAPSHOT: "1" }
const run = (...args) => spawnSync("bash", [script, ...args], { env, encoding: "utf8" })
const calls = () => (fs.existsSync(path.join(home, "calls")) ? fs.readFileSync(path.join(home, "calls"), "utf8").trim().split("\n") : [])

try {
  // The bar by section, with names; hidden ones are the bar widgets turned off,
  // but not one that a turned-on copy stands in for.
  const bar = JSON.parse(run("--bar", "--json").stdout)
  assert.deepStrictEqual(bar.sections.right, [{ id: "omarchy.weather", name: "Weather" }, { id: "omarchy.clock", name: "Clock" }])
  // The tray, which holds the drawer's items, is marked as such.
  assert.deepStrictEqual(bar.sections.left, [{ id: "me.tray", name: "My tray", drawer: true }])
  assert.deepStrictEqual(bar.hidden, [{ id: "omarchy.media", name: "Media" }])

  // Hide Weather, show Media at the front of the right, Clock after it.
  const r = run("--bar-layout", JSON.stringify({ sections: { right: ["omarchy.media", "omarchy.clock"] }, hidden: ["omarchy.weather"] }))
  assert.strictEqual(r.status, 0, r.stderr)
  assert.deepStrictEqual(calls(), [
    "plugin disable omarchy.weather",
    "plugin enable omarchy.media --section right --index 0",
    "bar move omarchy.clock --section right --index 1",
  ])

  // Unknown widgets, sections or odd ids are refused before anything runs.
  fs.rmSync(path.join(home, "calls"), { force: true })
  for (const bad of [
    { sections: { right: ["not.a.widget"] } },
    { sections: { middle: ["omarchy.clock"] } },
    { sections: { right: ["omarchy.clock; rm -rf ~"] } },
    { sections: { right: "omarchy.clock" } },
    { hidden: ["omarchy.dock"] },
  ]) {
    assert.strictEqual(run("--bar-layout", JSON.stringify(bad)).status, 1, JSON.stringify(bad))
  }
  assert.strictEqual(run("--bar-layout", "not json").status, 1)
  assert.deepStrictEqual(calls(), [])

  // With Control Center on the bar, the widgets it stands in for are unseen
  // there and left out; so is the bar icons helper, always.
  plugins.push({ id: "macos-theme.control-center", name: "Control Center", kinds: ["bar-widget"], enabled: true, clonedFrom: "" },
    { id: "omarchy.network", name: "Network", kinds: ["bar-widget"], enabled: true, clonedFrom: "" },
    { id: "macos-theme.bar-icons", name: "macOS icons", kinds: ["bar-widget"], enabled: true, clonedFrom: "" })
  fs.writeFileSync(path.join(home, "plugins.json"), JSON.stringify(plugins))
  const layout = { left: [{ id: "macos-theme.bar-icons" }], right: [{ id: "omarchy.network" }, { id: "omarchy.clock" }, { id: "macos-theme.control-center" }] }
  fs.writeFileSync(path.join(home, ".config/omarchy/shell.json"), JSON.stringify({ bar: { layout } }))
  let listed = JSON.parse(run("--bar", "--json").stdout)
  assert.deepStrictEqual(listed.sections.left, [])
  assert.deepStrictEqual(listed.sections.right.map((w) => w.id), ["omarchy.clock", "macos-theme.control-center"])
  // Without it, they are listed again.
  layout.right.pop()
  fs.writeFileSync(path.join(home, ".config/omarchy/shell.json"), JSON.stringify({ bar: { layout } }))
  listed = JSON.parse(run("--bar", "--json").stdout)
  assert.deepStrictEqual(listed.sections.right.map((w) => w.id), ["omarchy.network", "omarchy.clock"])
} finally {
  fs.rmSync(home, { recursive: true, force: true })
}

console.log("bar layout: ok")
