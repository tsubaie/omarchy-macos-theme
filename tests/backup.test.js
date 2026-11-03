// Snapshots, restore, export and import, in throwaway homes with a fake
// omarchy command. Run with: node tests/backup.test.js
const assert = require("assert")
const { spawnSync } = require("child_process")
const fs = require("fs")
const os = require("os")
const path = require("path")

const script = path.join(__dirname, "..", "install.sh")
const homes = []

function makeHome() {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "macos-theme-backup-"))
  homes.push(home)
  const bin = path.join(home, "bin")
  fs.mkdirSync(bin)
  fs.writeFileSync(path.join(bin, "omarchy"), `#!/bin/sh
[ "$1 $2" = "theme current" ] && { cat "$HOME/current" 2>/dev/null || echo "Tokyo Night"; }
[ "$1 $2" = "theme list" ] && printf 'Macos\\nTokyo Night\\n'
[ "$1 $2" = "theme set" ] && echo "$3" > "$HOME/current"
exit 0
`, { mode: 0o755 })
  // Never the real one: it would reload the desktop running the tests.
  fs.writeFileSync(path.join(bin, "hyprctl"), "#!/bin/sh\nexit 0\n", { mode: 0o755 })
  const env = { ...process.env, HOME: home, XDG_CONFIG_HOME: path.join(home, ".config"), PATH: `${bin}:${process.env.PATH}` }
  delete env.MACOS_THEME_NO_SNAPSHOT
  const run = (...args) => {
    const r = spawnSync("bash", [script, ...args], { env, encoding: "utf8" })
    return { ...r, out: r.stdout + r.stderr }
  }
  const json = (...args) => JSON.parse(run(...args).stdout)
  const config = (p) => path.join(home, ".config", p)
  return { home, run, json, config }
}

try {
  // A first change snapshots how things were before the theme, and keeps it.
  const a = makeHome()
  assert.deepStrictEqual(a.json("--backups", "--json"), [])
  assert.strictEqual(a.run("--add", "dock").status, 0)
  let snaps = a.json("--backups", "--json")
  assert.strictEqual(snaps.length, 1)
  assert.strictEqual(snaps[0].original, true)
  assert.strictEqual(snaps[0].pinned, true)
  assert.strictEqual(snaps[0].note, "Added dock")
  const original = snaps[0].id

  // The next change's snapshot holds the dock; its note says what came after.
  assert.strictEqual(a.run("--add", "rows", "--set", "magnification=1.3").status, 0)
  snaps = a.json("--backups", "--json")
  assert.strictEqual(snaps.length, 2)
  assert.match(snaps[0].note, /Added rows/)
  assert.match(snaps[0].note, /magnification 1\.3/)
  assert.strictEqual(snaps[0].original, false)
  assert.strictEqual(a.json("--status", "--json").features.rows, true)

  // Restoring the first one puts everything back as it was before the theme,
  // after a snapshot of now that undoes the restore.
  const restored = a.run("--restore", original)
  assert.strictEqual(restored.status, 0, restored.out)
  let s = a.json("--status", "--json")
  assert.ok(Object.values(s.features).every((on) => on === false), JSON.stringify(s.features))
  assert.ok(!fs.existsSync(a.config("gtk-4.0/gtk.css")))
  snaps = a.json("--backups", "--json")
  assert.match(snaps[0].note, /^Before restoring/)
  assert.strictEqual(a.run("--restore", snaps[0].id).status, 0)
  s = a.json("--status", "--json")
  assert.strictEqual(s.features.dock, true)
  assert.strictEqual(s.features.rows, true)
  assert.strictEqual(s.settings.magnification, 1.3)

  // Plugins the theme doesn't manage are left alone by a restore.
  fs.mkdirSync(a.config("omarchy/plugins/someone.else"), { recursive: true })
  fs.writeFileSync(a.config("omarchy/plugins/someone.else/manifest.json"), "{}")
  assert.strictEqual(a.run("--restore", original).status, 0)
  assert.ok(fs.existsSync(a.config("omarchy/plugins/someone.else/manifest.json")))

  // Old snapshots go, but never the first.
  for (let i = 0; i < 12; i++) assert.strictEqual(a.run("--backup").status, 0)
  snaps = a.json("--backups", "--json")
  assert.strictEqual(snaps.length, 11)
  assert.ok(snaps.some((x) => x.id === original && x.pinned))

  // A damaged backup is refused before anything is removed, and leaves no
  // snapshot of its own behind.
  assert.strictEqual(a.run("--add", "dock").status, 0)
  snaps = a.json("--backups", "--json")
  const dockDir = a.config("omarchy/plugins/macos-theme.dock")
  assert.ok(fs.existsSync(dockDir))
  fs.writeFileSync(path.join(a.home, ".config/omarchy/macos-theme-backups/snapshots", snaps[0].id, "files.tar.gz"), "not a tarball")
  const damaged = a.run("--restore", snaps[0].id)
  assert.strictEqual(damaged.status, 1)
  assert.match(damaged.out, /damaged/)
  assert.ok(fs.existsSync(path.join(dockDir, "manifest.json")))
  assert.strictEqual(a.json("--backups", "--json").length, snaps.length)

  // Several in one second come newest first: -10 after -2, as numbers.
  const t = makeHome()
  const snapshots = t.config("omarchy/macos-theme-backups/snapshots")
  for (const id of ["20260101-000000", "20260101-000000-2", "20260101-000000-10", "20251231-235959"]) {
    fs.mkdirSync(path.join(snapshots, id), { recursive: true })
    fs.writeFileSync(path.join(snapshots, id, "meta.json"), JSON.stringify({ id, created: "", note: id, pinned: false, original: false }))
  }
  assert.deepStrictEqual(t.json("--backups", "--json").map((x) => x.id),
    ["20260101-000000-10", "20260101-000000-2", "20260101-000000", "20251231-235959"])
  // And one taken in a second that already has one is numbered after it.
  for (let i = 0; i < 3; i++) assert.strictEqual(t.run("--backup").status, 0)
  const taken = t.json("--backups", "--json").filter((x) => x.note === "Backed up by hand").map((x) => x.id)
  assert.strictEqual(new Set(taken).size, 3)
  for (const id of taken) assert.match(id, /^[0-9]{8}-[0-9]{6}(-[0-9]+)?$/)

  // Bad ids are refused.
  assert.strictEqual(a.run("--restore", "nope").status, 1)
  assert.strictEqual(a.run("--restore", "../../etc").status, 1)
  assert.strictEqual(a.run("--restore").status, 1)

  // Export: the pieces, settings, dock and widgets setup, and your own wallpapers.
  const b = makeHome()
  assert.strictEqual(b.run("--add", "theme", "--add", "dock", "--add", "widgets", "--set", "glass=0.85").status, 0)
  const shellJson = b.config("omarchy/shell.json")
  fs.writeFileSync(shellJson, JSON.stringify({ dock: { pinned: ["firefox.desktop"] }, widgets: { screen: "DP-1" }, bar: { mine: true } }))
  fs.writeFileSync(b.config("omarchy/themes/macos/backgrounds/mine.jpg"), "photo")
  const exported = b.run("--export", b.home)
  assert.strictEqual(exported.status, 0, exported.out)
  const file = fs.readdirSync(b.home).find((f) => /^macos-theme-.*\.tar\.gz$/.test(f))
  assert.ok(file, "the export is written into the folder")
  const exportPath = path.join(b.home, file)
  const listing = spawnSync("tar", ["-tzf", exportPath], { encoding: "utf8" }).stdout
  assert.match(listing, /backgrounds\/mine\.jpg/)
  assert.doesNotMatch(listing, /pawel/, "the theme's own wallpapers stay out")

  // Import elsewhere: the same pieces, settings, setup and wallpapers, and the
  // rest of shell.json untouched.
  const c = makeHome()
  fs.mkdirSync(c.config("omarchy"), { recursive: true })
  fs.writeFileSync(c.config("omarchy/shell.json"), JSON.stringify({ bar: { theirs: true } }))
  const imported = c.run("--import", exportPath)
  assert.strictEqual(imported.status, 0, imported.out)
  s = c.json("--status", "--json")
  assert.strictEqual(s.features.theme, true)
  assert.strictEqual(s.features.dock, true)
  assert.strictEqual(s.features.widgets, true)
  assert.strictEqual(s.settings.glass, 0.85)
  const shell = JSON.parse(fs.readFileSync(c.config("omarchy/shell.json"), "utf8"))
  assert.deepStrictEqual(shell.dock.pinned, ["firefox.desktop"])
  assert.strictEqual(shell.widgets.screen, "DP-1")
  assert.deepStrictEqual(shell.bar, { theirs: true })
  assert.strictEqual(fs.readFileSync(c.config("omarchy/themes/macos/backgrounds/mine.jpg"), "utf8"), "photo")
  assert.match(c.json("--backups", "--json")[0].note, /^Before importing/)

  // Anything but a profile and images in the file is refused, before it is unpacked.
  const evil = fs.mkdtempSync(path.join(os.tmpdir(), "macos-theme-evil-"))
  homes.push(evil)
  fs.writeFileSync(path.join(evil, "profile.json"), JSON.stringify({ format: 1, pieces: [] }))
  fs.writeFileSync(path.join(evil, "run.sh"), "echo hi")
  spawnSync("tar", ["-C", evil, "-czf", path.join(evil, "evil.tar.gz"), "profile.json", "run.sh"])
  const refused = c.run("--import", path.join(evil, "evil.tar.gz"))
  assert.strictEqual(refused.status, 1)
  assert.match(refused.out, /Not a macOS theme export/)
  fs.writeFileSync(path.join(evil, "profile.json"), JSON.stringify({ format: 99 }))
  spawnSync("tar", ["-C", evil, "-czf", path.join(evil, "future.tar.gz"), "profile.json"])
  assert.strictEqual(c.run("--import", path.join(evil, "future.tar.gz")).status, 1)
  assert.strictEqual(c.run("--import", path.join(evil, "missing.tar.gz")).status, 1)

  // A link in the file is refused, even with an image's name: it would copy
  // what it points to (a private key, say) into the theme.
  fs.writeFileSync(path.join(evil, "profile.json"), JSON.stringify({ format: 1, pieces: [] }))
  fs.writeFileSync(path.join(evil, "secret"), "private")
  fs.mkdirSync(path.join(evil, "backgrounds"))
  fs.symlinkSync(path.join(evil, "secret"), path.join(evil, "backgrounds/a.jpg"))
  spawnSync("tar", ["-C", evil, "-czf", path.join(evil, "link.tar.gz"), "profile.json", "backgrounds"])
  const linked = c.run("--import", path.join(evil, "link.tar.gz"))
  assert.strictEqual(linked.status, 1)
  assert.match(linked.out, /links/)
  assert.ok(!fs.existsSync(c.config("omarchy/themes/macos/backgrounds/a.jpg")))

  // An export from a version that let glass go lower still imports, at the least glass now takes.
  const oldGlass = path.join(evil, "old-glass")
  fs.mkdirSync(oldGlass)
  fs.writeFileSync(path.join(oldGlass, "profile.json"), JSON.stringify({ format: 1, pieces: ["theme"], settings: { glass: 0.6 } }))
  spawnSync("tar", ["-C", oldGlass, "-czf", path.join(evil, "old-glass.tar.gz"), "profile.json"])
  const lowered = c.run("--import", path.join(evil, "old-glass.tar.gz"))
  assert.strictEqual(lowered.status, 0, lowered.out)
  assert.strictEqual(c.json("--status", "--json").settings.glass, 0.75)

  // A restore that fails half-way puts back how things were, the theme's own
  // wallpapers too. A file where gtk-4.0 should be makes the move fail.
  const e = makeHome()
  assert.strictEqual(e.run("--add", "theme", "--add", "rows").status, 0)
  assert.ok(fs.existsSync(e.config("gtk-4.0/gtk.css")))
  assert.strictEqual(e.run("--backup").status, 0)
  const withGtk = e.json("--backups", "--json")[0].id
  fs.rmSync(e.config("gtk-4.0"), { recursive: true })
  fs.writeFileSync(e.config("gtk-4.0"), "in the way")
  const failed = e.run("--restore", withGtk)
  assert.strictEqual(failed.status, 1)
  assert.match(failed.out, /put back as they were/)
  assert.strictEqual(fs.readFileSync(e.config("gtk-4.0"), "utf8"), "in the way")
  for (const w of fs.readdirSync(path.join(__dirname, "..", "theme/backgrounds")))
    assert.ok(fs.existsSync(e.config(`omarchy/themes/macos/backgrounds/${w}`)), w)
  assert.strictEqual(e.json("--status", "--json").features.theme, true)
  assert.deepStrictEqual(fs.readdirSync(e.config("")).filter((f) => f.startsWith(".macos-theme-restore")), [])

  // Removing the current theme is refused before its snapshot is taken.
  const d = makeHome()
  assert.strictEqual(d.run("--add", "theme").status, 0)
  fs.writeFileSync(path.join(d.home, "current"), "Macos")
  const count = d.json("--backups", "--json").length
  const refusedRemove = d.run("--remove", "theme")
  assert.strictEqual(refusedRemove.status, 1)
  assert.match(refusedRemove.out, /Switch to another theme first/)
  assert.strictEqual(d.json("--backups", "--json").length, count)

  // A preview edits only the theme Omarchy is showing, never the theme
  // folder, so a quit mid-drag leaves nothing saved.
  const shown = path.join(d.home, ".local/state/omarchy/current/theme")
  fs.mkdirSync(shown, { recursive: true })
  fs.cpSync(d.config("omarchy/themes/macos"), shown, { recursive: true })
  const lookBefore = fs.readFileSync(d.config("omarchy/themes/macos/look.lua"), "utf8")
  const previewed = d.run("--preview", "--set", "glass=0.9")
  assert.strictEqual(previewed.status, 0, previewed.out)
  assert.strictEqual(fs.readFileSync(d.config("omarchy/themes/macos/look.lua"), "utf8"), lookBefore)
  assert.match(fs.readFileSync(path.join(shown, "look.lua"), "utf8"), /opacity = "1 0\.9"/)
  assert.strictEqual(d.json("--backups", "--json").length, count)
} finally {
  for (const home of homes) fs.rmSync(home, { recursive: true, force: true })
}

console.log("backups, export and import: ok")
