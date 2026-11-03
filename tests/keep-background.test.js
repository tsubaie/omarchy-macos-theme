// Backgrounds: installing the theme keeps the one showing now, and choosing,
// adding and restoring them, in a throwaway home with a fake omarchy.
// Run with: node tests/keep-background.test.js
const assert = require("assert")
const { spawnSync } = require("child_process")
const fs = require("fs")
const os = require("os")
const path = require("path")

const script = path.join(__dirname, "..", "install.sh")

// A home where Tokyo Night is current, its backgrounds where `omarchy theme dir`
// says, and the background link pointing wherever `background` says.
function makeHome(background, remembered) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "macos-theme-bg-"))
  const bin = path.join(home, "bin")
  fs.mkdirSync(bin)
  // `theme set` notes what the theme remembered at that moment, as Omarchy reads
  // it then; `theme bg set` points the background link, as Omarchy's does.
  fs.writeFileSync(path.join(bin, "omarchy"), `#!/bin/sh
state="$HOME/.local/state/omarchy/theme-backgrounds/macos"
[ "$1 $2" = "theme current" ] && { cat "$HOME/current" 2>/dev/null || echo "Tokyo Night"; }
[ "$1 $2" = "theme list" ] && printf 'Macos\\nTokyo Night\\n'
[ "$1 $2" = "theme dir" ] && { [ -n "$3" ] || exit 1; echo "$HOME/themes/$3"; }
if [ "$1 $2" = "theme set" ]; then
  # Named as Omarchy names it once current.
  if [ "$3" = macos ]; then echo Macos; else echo "$3"; fi > "$HOME/current"
  cat "$state" > "$HOME/remembered" 2>/dev/null || : > "$HOME/remembered"
fi
[ "$1 $2 $3" = "theme bg set" ] && ln -nsf "$(realpath "$4")" "$HOME/.local/state/omarchy/current/background"
exit 0
`, { mode: 0o755 })
  fs.writeFileSync(path.join(bin, "fc-list"), "#!/bin/sh\necho Inter\n", { mode: 0o755 })
  // A restore reloads Hyprland; nothing here may reach the real one.
  fs.writeFileSync(path.join(bin, "hyprctl"), "#!/bin/sh\nexit 0\n", { mode: 0o755 })

  const current = path.join(home, ".local/state/omarchy/current")
  fs.mkdirSync(path.join(current, "theme/backgrounds"), { recursive: true })
  fs.writeFileSync(path.join(current, "theme.name"), "tokyo-night\n")
  fs.writeFileSync(path.join(current, "theme/backgrounds/1-totoro.webp"), "")
  fs.mkdirSync(path.join(home, "themes/tokyo-night/backgrounds"), { recursive: true })
  fs.writeFileSync(path.join(home, "themes/tokyo-night/backgrounds/1-totoro.webp"), "")
  fs.mkdirSync(path.join(home, "Pictures"))
  fs.writeFileSync(path.join(home, "Pictures/mine.jpg"), "mine")
  if (background) fs.symlinkSync(background(home), path.join(current, "background"))
  if (remembered) {
    fs.mkdirSync(path.join(home, ".local/state/omarchy/theme-backgrounds"), { recursive: true })
    fs.writeFileSync(path.join(home, ".local/state/omarchy/theme-backgrounds/macos"), remembered(home) + "\n")
  }

  const env = { ...process.env, DBUS_SESSION_BUS_ADDRESS: "", HYPRLAND_INSTANCE_SIGNATURE: "", XDG_RUNTIME_DIR: home, HOME: home, XDG_CONFIG_HOME: path.join(home, ".config"), PATH: `${bin}:${process.env.PATH}`, USER: "me" }
  const run = (...args) => spawnSync("bash", [script, ...args], { env, encoding: "utf8" })
  const installed = run("--add", "theme")
  assert.strictEqual(installed.status, 0, installed.stderr)
  const at = fs.readFileSync(path.join(home, "remembered"), "utf8").trim()
  return { home, at, run, done: () => fs.rmSync(home, { recursive: true, force: true }) }
}
const once = (...args) => { const h = makeHome(...args); h.done(); return h }

// Installing: your own picture is remembered, so the switch keeps it.
{
  const { home, at } = once((h) => path.join(h, "Pictures/mine.jpg"))
  assert.strictEqual(at, path.join(home, "Pictures/mine.jpg"))
}
// One that came with the theme current now: that theme's own copy, which the
// switch doesn't replace, not the one in current/theme/ it does.
{
  const { home, at } = once((h) => path.join(h, ".local/state/omarchy/current/theme/backgrounds/1-totoro.webp"))
  assert.strictEqual(at, path.join(home, "themes/tokyo-night/backgrounds/1-totoro.webp"))
}
// The theme remembers one already: left as it is.
{
  const { home, at } = once((h) => path.join(h, "Pictures/mine.jpg"), (h) => path.join(h, "themes/macos-own.jpg"))
  assert.strictEqual(at, path.join(home, "themes/macos-own.jpg"))
}
// No background at all, or one that's gone: nothing remembered, so the theme's own.
assert.strictEqual(once(null).at, "")
assert.strictEqual(once((h) => path.join(h, "Pictures/gone.jpg")).at, "")

// Choosing, adding and restoring, with the theme current.
{
  const h = makeHome((home) => path.join(home, "Pictures/mine.jpg"))
  try {
    const link = path.join(h.home, ".local/state/omarchy/current/background")
    const list = () => JSON.parse(h.run("--backgrounds", "--json").stdout)
    const themeBg = list().theme[0]
    assert.ok(themeBg && themeBg.endsWith("1-pawel-czerwinski.jpg"), JSON.stringify(list()))
    assert.strictEqual(list().current, path.join(h.home, "Pictures/mine.jpg"))

    // Adding: copied into your folder; a different picture by the same name gets one of its own.
    fs.mkdirSync(path.join(h.home, "Other"))
    fs.writeFileSync(path.join(h.home, "Other/mine.jpg"), "another")
    const added = h.run("--add-background", path.join(h.home, "Pictures/mine.jpg"), "--add-background", path.join(h.home, "Other/mine.jpg"))
    assert.strictEqual(added.status, 0, added.stderr)
    const folder = path.join(h.home, ".config/omarchy/backgrounds/macos")
    assert.deepStrictEqual(list().yours, [path.join(folder, "mine-2.jpg"), path.join(folder, "mine.jpg")])
    assert.strictEqual(h.run("--add-background", path.join(h.home, "Pictures/mine.jpg")).stdout.trim(), path.join(folder, "mine.jpg"))
    assert.notStrictEqual(h.run("--add-background", path.join(h.home, "remembered")).status, 0)

    // Choosing: a backup first, then shown and remembered; the list reports it
    // by its place in the theme's folder.
    const before = JSON.parse(h.run("--backups", "--json").stdout).length
    const chose = h.run("--background", themeBg)
    assert.strictEqual(chose.status, 0, chose.stderr)
    const backups = JSON.parse(h.run("--backups", "--json").stdout)
    assert.strictEqual(backups.length, before + 1)
    assert.strictEqual(backups[0].note, "Background 1-pawel-czerwinski.jpg")
    assert.strictEqual(fs.realpathSync(link), fs.realpathSync(themeBg))
    assert.strictEqual(list().current, themeBg)
    assert.notStrictEqual(h.run("--background", path.join(h.home, "remembered")).status, 0)

    // Restoring the backup it took puts the background back.
    const restored = h.run("--restore", backups[0].id)
    assert.strictEqual(restored.status, 0, restored.stderr)
    assert.strictEqual(fs.realpathSync(link), path.join(h.home, "Pictures/mine.jpg"))
  } finally {
    h.done()
  }
}

console.log("keep background: ok")
