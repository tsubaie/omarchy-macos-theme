// The theme changes only what it made: clones, icons, the plugins it turned
// off and the bar it arranged, and shell.json kept as it is (a symlink, its
// mode). Throwaway homes with a fake omarchy. Run with: node tests/ownership.test.js
const assert = require("assert")
const { spawnSync } = require("child_process")
const fs = require("fs")
const os = require("os")
const path = require("path")

const script = path.join(__dirname, "..", "install.sh")
const user = "someone"
const homes = []

function makeHome() {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "macos-theme-own-"))
  homes.push(home)
  const bin = path.join(home, "bin")
  fs.mkdirSync(bin)
  // Clones are named after you, as Omarchy's are; `plugin list` reads
  // plugins.json; every enable is logged.
  fs.writeFileSync(path.join(bin, "omarchy"), `#!/bin/sh
[ "$1 $2" = "theme current" ] && { cat "$HOME/current" 2>/dev/null || echo "Tokyo Night"; }
[ "$1 $2" = "theme list" ] && printf 'Macos\\nTokyo Night\\n'
[ "$1 $2" = "plugin list" ] && cat "$HOME/plugins.json" 2>/dev/null
[ "$1 $2" = "plugin enable" ] && echo "$3" >> "$HOME/enabled.log"
if [ "$1 $2" = "plugin clone" ]; then
  dir="$XDG_CONFIG_HOME/omarchy/plugins/$USER.\${3#omarchy.}"
  [ -e "$dir" ] && exit 1
  mkdir -p "$dir" && touch "$dir/Menu.qml" "$dir/Workspaces.qml"
  printf '{ "omarchy": { "clonedFrom": "%s" } }' "$3" > "$dir/manifest.json"
  # Worded unlike today's Omarchy: the theme mustn't depend on the wording.
  echo "Made a copy of $3"
fi
exit 0
`, { mode: 0o755 })
  for (const quiet of ["hyprctl", "omarchy-shell"]) fs.writeFileSync(path.join(bin, quiet), "#!/bin/sh\nexit 0\n", { mode: 0o755 })
  const env = { ...process.env, DBUS_SESSION_BUS_ADDRESS: "", HYPRLAND_INSTANCE_SIGNATURE: "", XDG_RUNTIME_DIR: home, HOME: home, USER: user, XDG_CONFIG_HOME: path.join(home, ".config"), PATH: `${bin}:${process.env.PATH}` }
  delete env.MACOS_THEME_NO_SNAPSHOT
  const run = (...args) => {
    const r = spawnSync("bash", [script, ...args], { env, encoding: "utf8" })
    return { ...r, out: r.stdout + r.stderr }
  }
  const status = () => JSON.parse(run("--status", "--json").stdout)
  const config = (p) => path.join(home, ".config", p)
  return { home, run, status, config }
}

try {
  // A clone of your own is never patched, replaced or removed: not by an add,
  // a remove, an uninstall or a restore.
  const a = makeHome()
  for (const [name, file] of [["menu", "Menu.qml"], ["lock", "LockView.qml"]]) {
    const dir = a.config(`omarchy/plugins/${user}.${name}`)
    fs.mkdirSync(dir, { recursive: true })
    fs.writeFileSync(path.join(dir, "manifest.json"), `{ "omarchy": { "clonedFrom": "omarchy.${name}" } }`)
    fs.writeFileSync(path.join(dir, file), "mine")
  }
  const mine = () => ["menu/Menu.qml", "lock/LockView.qml"].map((f) => fs.readFileSync(a.config(`omarchy/plugins/${user}.${f}`), "utf8"))
  const added = a.run("--add", "wide-menu", "--add", "lock")
  assert.strictEqual(added.status, 0, added.out)
  assert.match(added.out, /someone\.menu is a clone of omarchy\.menu of your own/)
  assert.match(added.out, /someone\.lock is a clone of omarchy\.lock of your own/)
  assert.deepStrictEqual(mine(), ["mine", "mine"])
  assert.strictEqual(a.status().features["wide-menu"], false)
  assert.strictEqual(a.status().features.lock, false)
  assert.strictEqual(a.run("--backup").status, 0)
  const snap = JSON.parse(a.run("--backups", "--json").stdout)[0].id
  assert.strictEqual(a.run("--uninstall").status, 0)
  assert.strictEqual(a.run("--restore", snap).status, 0)
  assert.deepStrictEqual(mine(), ["mine", "mine"])
  // A snapshot from before the theme told its clones from yours holds yours
  // too; restoring it leaves yours as it is, with nothing put inside it.
  const snapDir = path.join(a.config("omarchy/macos-theme-backups/snapshots"), snap)
  spawnSync("tar", ["-C", a.config(""), "-czf", path.join(snapDir, "files.tar.gz"), `omarchy/plugins/${user}.menu`])
  fs.writeFileSync(a.config(`omarchy/plugins/${user}.menu/Menu.qml`), "mine, changed since")
  const old = a.run("--restore", snap)
  assert.strictEqual(old.status, 0, old.out)
  assert.strictEqual(fs.readFileSync(a.config(`omarchy/plugins/${user}.menu/Menu.qml`), "utf8"), "mine, changed since")
  assert.ok(!fs.existsSync(a.config(`omarchy/plugins/${user}.menu/${user}.menu`)))

  // A restore leaves the theme's workspaces clone on the bar, whether or not
  // the snapshot holds it (older ones never did).
  const w = makeHome()
  assert.strictEqual(w.run("--backup").status, 0)
  const bare = JSON.parse(w.run("--backups", "--json").stdout)[0].id
  assert.strictEqual(w.run("--add", "menubar").status, 0)
  const ws = w.config(`omarchy/plugins/${user}.workspaces`)
  assert.ok(fs.existsSync(path.join(ws, ".macos-theme")))
  const restored = w.run("--restore", bare)
  assert.strictEqual(restored.status, 0, restored.out)
  assert.ok(fs.existsSync(path.join(ws, "manifest.json")))
  assert.ok(!fs.existsSync(w.config("omarchy/plugins/macos-theme.menubar")))

  // The theme's own clone stays the theme's even when its patch didn't take.
  const b = makeHome()
  const menu = b.run("--add", "wide-menu")
  assert.match(menu.out, /Could not patch/)
  assert.ok(fs.existsSync(b.config(`omarchy/plugins/${user}.menu/.macos-theme`)))
  assert.strictEqual(b.status().features["wide-menu"], true)
  assert.strictEqual(b.run("--remove", "wide-menu").status, 0)
  assert.ok(!fs.existsSync(b.config(`omarchy/plugins/${user}.menu`)))

  // MacTahoe installed some other way is used, reported as such, and left in
  // place; the theme's own (marked) is removed.
  const c = makeHome()
  const icons = path.join(c.home, ".local/share/icons")
  fs.mkdirSync(path.join(icons, "MacTahoe-dark"), { recursive: true })
  let s = c.status()
  assert.strictEqual(s.features.icons, false)
  assert.strictEqual(s["icons-outside"], true)
  assert.match(c.run("--add", "icons").out, /already installed, not by the theme/)
  assert.match(c.run("--remove", "icons").out, /weren't installed by the theme/)
  assert.ok(fs.existsSync(path.join(icons, "MacTahoe-dark")))
  for (const t of ["MacTahoe", "MacTahoe-dark", "MacTahoe-light"]) {
    fs.mkdirSync(path.join(icons, t), { recursive: true })
    fs.writeFileSync(path.join(icons, t, ".macos-theme"), "")
  }
  assert.strictEqual(c.status().features.icons, true)
  assert.strictEqual(c.run("--remove", "icons").status, 0)
  assert.deepStrictEqual(fs.readdirSync(icons), [])
  // Installed by the theme before it marked them: its large folder icons
  // copied over the small ones.
  for (const size of ["16", "scalable"]) {
    fs.mkdirSync(path.join(icons, "MacTahoe-dark/places", size), { recursive: true })
    fs.writeFileSync(path.join(icons, "MacTahoe-dark/places", size, "folder.svg"), "<svg/>")
  }
  assert.strictEqual(c.status().features.icons, true)
  assert.strictEqual(c.run("--remove", "icons").status, 0)
  assert.ok(!fs.existsSync(path.join(icons, "MacTahoe-dark")))

  // Removing a piece turns back on what was on before the theme, not more: a
  // capsule you had turned off stays off.
  const d = makeHome()
  fs.writeFileSync(path.join(d.home, "plugins.json"), JSON.stringify([
    { id: "omarchy.osd", enabled: false, clonedFrom: "" },
    { id: "omarchy.dock", enabled: true, clonedFrom: "" },
  ]))
  assert.strictEqual(d.run("--add", "osd", "--add", "dock").status, 0)
  fs.rmSync(path.join(d.home, "enabled.log"), { force: true })
  assert.strictEqual(d.run("--remove", "osd", "--remove", "dock").status, 0)
  assert.deepStrictEqual(fs.readFileSync(path.join(d.home, "enabled.log"), "utf8").trim().split("\n"), ["omarchy.dock"])
  // With all of it gone the record goes too: a dock you turn off before the
  // next install stays off when that one is removed.
  assert.ok(!fs.existsSync(d.config("omarchy/macos-theme-backups/plugins-before-theme.json")))
  fs.writeFileSync(path.join(d.home, "plugins.json"), JSON.stringify([{ id: "omarchy.dock", enabled: false, clonedFrom: "" }]))
  assert.strictEqual(d.run("--add", "dock").status, 0)
  fs.rmSync(path.join(d.home, "enabled.log"), { force: true })
  assert.strictEqual(d.run("--remove", "dock").status, 0)
  assert.ok(!fs.existsSync(path.join(d.home, "enabled.log")))

  // The bar goes back to how it was before the menu bar, keeping what other
  // plugins put on it since and none of the menu bar's.
  const shellJson = d.config("omarchy/shell.json")
  const before = { left: [{ id: "omarchy.workspaces" }], right: [{ id: "omarchy.clock" }] }
  fs.writeFileSync(shellJson, JSON.stringify({ bar: { layout: before } }))
  assert.strictEqual(d.run("--add", "menubar").status, 0)
  fs.writeFileSync(shellJson, JSON.stringify({ bar: { layout: {
    left: [{ id: "macos-theme.app-name" }, { id: `${user}.workspaces` }],
    right: [{ id: "macos-theme.control-center" }, { id: "omarchy.clock" }, { id: "other.widget" }],
  } } }))
  const removed = d.run("--remove", "menubar")
  assert.strictEqual(removed.status, 0, removed.out)
  assert.deepStrictEqual(JSON.parse(fs.readFileSync(shellJson, "utf8")).bar.layout, {
    left: [{ id: "omarchy.workspaces" }],
    right: [{ id: "omarchy.clock" }, { id: "other.widget" }],
  })

  // shell.json kept in dotfiles stays a symlink there, with its mode.
  const e = makeHome()
  const dotfile = path.join(e.home, "dotfiles/shell.json")
  fs.mkdirSync(path.dirname(dotfile))
  fs.writeFileSync(dotfile, "{}", { mode: 0o644 })
  fs.mkdirSync(e.config("omarchy"), { recursive: true })
  fs.symlinkSync(dotfile, e.config("omarchy/shell.json"))
  assert.strictEqual(e.run("--set", "magnification=1.3").status, 0)
  assert.ok(fs.lstatSync(e.config("omarchy/shell.json")).isSymbolicLink())
  assert.strictEqual(JSON.parse(fs.readFileSync(dotfile, "utf8")).dock.magnification, 1.3)
  assert.strictEqual(fs.statSync(dotfile).mode & 0o777, 0o644)

  // The macOS notifications: added, a marked clone drawn by the theme's card,
  // with its update hook; removed, both gone and Omarchy's own turned back on,
  // since one notifications service runs at a time.
  {
    const n = makeHome()
    const clone = n.config(`omarchy/plugins/${user}.notifications`)
    const hook = path.join(n.home, ".config/omarchy/hooks/post-update.d/macos-theme-notifications")
    const added = n.run("--add", "notifications")
    assert.strictEqual(added.status, 0, added.out)
    assert.match(fs.readFileSync(path.join(clone, "Toast.qml"), "utf8"), /One notification card, as macOS draws one/)
    assert.ok(fs.existsSync(path.join(clone, ".macos-theme")), "the clone is marked as the theme's")
    assert.ok(fs.existsSync(hook), "the update hook is in place")
    assert.strictEqual(n.status().features.notifications, true)
    fs.rmSync(path.join(n.home, "enabled.log"), { force: true })
    const removed = n.run("--remove", "notifications")
    assert.strictEqual(removed.status, 0, removed.out)
    assert.ok(!fs.existsSync(clone), "the clone is gone")
    assert.ok(!fs.existsSync(hook), "the update hook is gone")
    assert.match(fs.readFileSync(path.join(n.home, "enabled.log"), "utf8"), /^omarchy\.notifications$/m)
    assert.strictEqual(n.status().features.notifications, false)
  }
  // A notifications clone of your own is never replaced or removed.
  {
    const n = makeHome()
    const mine = n.config(`omarchy/plugins/${user}.notifications`)
    fs.mkdirSync(mine, { recursive: true })
    fs.writeFileSync(path.join(mine, "manifest.json"), '{ "omarchy": { "clonedFrom": "omarchy.notifications" } }')
    fs.writeFileSync(path.join(mine, "Toast.qml"), "mine")
    const added = n.run("--add", "notifications")
    assert.strictEqual(added.status, 0, added.out)
    assert.match(added.out, /someone\.notifications is a clone of omarchy\.notifications of your own/)
    assert.strictEqual(n.run("--remove", "notifications").status, 0)
    assert.strictEqual(fs.readFileSync(path.join(mine, "Toast.qml"), "utf8"), "mine")
  }
} finally {
  for (const home of homes) fs.rmSync(home, { recursive: true, force: true })
}

console.log("ownership: ok")
