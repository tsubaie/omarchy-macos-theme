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
# A plugin Omarchy refuses to enable, as $FAIL_ENABLE names it.
[ "$1 $2" = "plugin enable" ] && [ "$3" = "$FAIL_ENABLE" ] && exit 1
if [ "$1 $2" = "plugin clone" ]; then
  dir="$XDG_CONFIG_HOME/omarchy/plugins/$USER.\${3#omarchy.}"
  mkdir -p "$dir" && touch "$dir/Menu.qml"
  printf '{ "omarchy": { "clonedFrom": "%s" } }' "$3" > "$dir/manifest.json"
  echo "Cloned $3 to $dir and switched"
fi
# A bar move leaves a mark in shell.json, so a test can tell the bar was rearranged.
if [ "$1" = "bar" ] && [ -s "$XDG_CONFIG_HOME/omarchy/shell.json" ]; then
  jq '.bar.layout.left = ((.bar.layout.left // []) + [{"id": "moved"}])' "$XDG_CONFIG_HOME/omarchy/shell.json" > "$XDG_CONFIG_HOME/omarchy/shell.json.tmp" &&
    mv "$XDG_CONFIG_HOME/omarchy/shell.json.tmp" "$XDG_CONFIG_HOME/omarchy/shell.json"
fi
exit 0
`, { mode: 0o755 })
// The shell's log for --doctor: one binding loop and one error from the theme's
// plugins, and lines every shell logs, which --doctor leaves out.
fs.writeFileSync(path.join(bin, "qs"), `#!/bin/sh
[ "$1" = log ] || exit 0
[ -e "$HOME/no-shell" ] && exit 1
[ -e "$HOME/quiet-log" ] && { echo " DEBUG qml: all quiet"; exit 0; }
P="file://$XDG_CONFIG_HOME/omarchy/plugins"
echo "  WARN scene: QML AppName at $P/macos-theme.dock/Dock.qml[11:1]: Binding loop detected for property \\"implicitWidth\\":"
echo " ERROR scene: $P/macos-theme.dock/Dock.qml[40:3]: TypeError: Cannot read property 'x' of null"
echo "  WARN scene: QML ShellIpc at $P/macos-theme.dock/Dock.qml[9:3]: Handler was registered but will not be used because another handler is registered"
echo "  INFO: qs://$XDG_CONFIG_HOME/omarchy/plugins/macos-theme.dock/Dock.qml: Object or context destroyed during incubation"
echo "  WARN scene: QML Thing at $P/someone.else/Thing.qml[1:1]: Binding loop detected"
`, { mode: 0o755 })
// Inter installed, whatever this machine has, so a warning about it can't show up.
fs.writeFileSync(path.join(bin, "fc-list"), "#!/bin/sh\necho Inter\n", { mode: 0o755 })

const env = { ...process.env, HOME: home, XDG_CONFIG_HOME: path.join(home, ".config"), PATH: `${bin}:${process.env.PATH}`, THEME: "Tokyo Night", USER: "me" }
const run = (...args) => spawnSync("bash", [script, ...args], { env, encoding: "utf8" })
const status = () => JSON.parse(execFileSync("bash", [script, "--status", "--json"], { env, encoding: "utf8" }))
const pieces = ["theme", "rows", "icons", "wide-menu", "dock", "switcher", "osd", "dictation-hud", "menubar", "bar-icons", "lock", "widgets"]

try {
  // stdout says what was done; stderr is for warnings only, which Studio shows
  // as such: a plain install has none, the HUD's Voxtype tip is one, and it
  // comes once, not again on every reinstall.
  const plain = run("--add", "dock")
  assert.strictEqual(plain.status, 0, plain.stderr)
  assert.strictEqual(plain.stderr, "")
  const hud = run("--add", "dictation-hud")
  assert.match(hud.stderr, /Voxtype/)
  assert.doesNotMatch(hud.stdout, /Voxtype/)
  assert.strictEqual(run("--add", "dictation-hud").stderr, "")

  // --doctor: what the shell logged against the theme's plugins, not the
  // noise every shell logs or other plugins' problems; nothing logged is a pass.
  const doctor = run("--doctor")
  assert.strictEqual(doctor.status, 1)
  assert.match(doctor.stderr, /macos-theme\.dock\/Dock\.qml\[11:1\]: Binding loop/)
  assert.match(doctor.stderr, /TypeError/)
  assert.doesNotMatch(doctor.stderr, /Handler was registered|incubation|someone\.else/)
  fs.writeFileSync(path.join(home, "quiet-log"), "")
  assert.strictEqual(run("--doctor").status, 0)
  fs.rmSync(path.join(home, "quiet-log"))
  // No shell running, so no log: that is a failure, not a pass.
  fs.writeFileSync(path.join(home, "no-shell"), "")
  const noShell = run("--doctor")
  assert.strictEqual(noShell.status, 1)
  assert.match(noShell.stderr, /Couldn't read the shell's log/)
  fs.rmSync(path.join(home, "no-shell"))
  assert.strictEqual(run("--remove", "dock", "--remove", "dictation-hud").status, 0)

  // A fresh home: nothing installed, and every piece is reported.
  let s = status()
  assert.deepStrictEqual(Object.keys(s.features), pieces)
  assert.ok(Object.values(s.features).every((on) => on === false))
  assert.strictEqual(s.active, false)
  assert.deepStrictEqual(s.settings, { glass: 0.7, "web-glass": 1, snapping: 1, "drop-follow": 1, blur: 10, "title-bars": 1, "traffic-lights": 14, magnification: 1.75, "dock-size": 48 })

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
  // After omarchy-update, a hook brings Omarchy's new lock code into the clone, keeping the macOS view.
  const hook = path.join(home, ".config/omarchy/hooks/post-update.d/macos-theme-lock")
  const omarchyLock = path.join(home, "omarchy/shell/plugins/lock")
  fs.mkdirSync(omarchyLock, { recursive: true })
  fs.writeFileSync(path.join(omarchyLock, "Service.qml"), "new auth")
  fs.writeFileSync(path.join(omarchyLock, "LockView.qml"), "Omarchy's view")
  assert.strictEqual(spawnSync("bash", [hook], { env: { ...env, OMARCHY_PATH: path.join(home, "omarchy") } }).status, 0)
  assert.strictEqual(fs.readFileSync(path.join(lockDir, "Service.qml"), "utf8"), "new auth")
  assert.match(fs.readFileSync(path.join(lockDir, "LockView.qml"), "utf8"), /The macOS lock screen/)
  assert.strictEqual(run("--remove", "lock").status, 0)
  assert.strictEqual(status().features.lock, false)
  assert.ok(!fs.existsSync(lockDir))
  assert.ok(!fs.existsSync(hook))

  // A plugin that won't enable is left out; the others still install, and the run fails naming it.
  const unenabled = spawnSync("bash", [script, "--add", "osd", "--add", "widgets"], { env: { ...env, FAIL_ENABLE: "macos-theme.osd" }, encoding: "utf8" })
  assert.strictEqual(unenabled.status, 1)
  assert.match(unenabled.stderr, /Could not install macos-theme\.osd/)
  assert.strictEqual(status().features.osd, false)
  assert.strictEqual(status().features.widgets, true)
  assert.strictEqual(run("--remove", "widgets").status, 0)

  // One run at a time: a live run's lock turns this one away before it changes anything;
  // a killed run's lock is taken over.
  const backups = path.join(home, ".config/omarchy/macos-theme-backups")
  const lock = path.join(backups, ".lock")
  fs.mkdirSync(lock)
  fs.writeFileSync(path.join(lock, "pid"), String(process.pid))
  const busy = run("--add", "switcher")
  assert.strictEqual(busy.status, 1)
  assert.match(busy.stderr, /Another run of install\.sh/)
  assert.strictEqual(status().features.switcher, false)
  fs.writeFileSync(path.join(lock, "pid"), "999999999")
  assert.strictEqual(run("--add", "switcher").status, 0)
  assert.ok(!fs.existsSync(lock))
  assert.strictEqual(run("--remove", "switcher").status, 0)

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
  // A reinstall leaves no copy of the old theme behind: its snapshot has it.
  assert.deepStrictEqual(fs.readdirSync(backups).filter((d) => d.startsWith("macos.")), [])
  // GTK's blur comes from the current theme's folder, so it goes when another theme is current;
  // the global import older versions added is replaced.
  const gtkCss = path.join(home, ".config/gtk-4.0/gtk.css")
  assert.match(fs.readFileSync(path.join(themeDir, "glass.css"), "utf8"), /default\/gtk\/glass\.css/)
  fs.writeFileSync(gtkCss, fs.readFileSync(gtkCss, "utf8").replace("current/theme/glass.css", "x").replace(/@import url\("file:\/\/.*x"\);/, '@import url("file:///usr/share/omarchy/default/gtk/glass.css");'))
  assert.strictEqual(run("--add", "theme").status, 0)
  const gtk = fs.readFileSync(gtkCss, "utf8")
  assert.match(gtk, /current\/theme\/glass\.css/)
  assert.doesNotMatch(gtk, /default\/gtk\/glass\.css/)

  // Settings: glass goes into look.lua and stays through a reinstall; magnification
  // goes into the dock's section of shell.json, next to what was there.
  const shellJson = path.join(home, ".config/omarchy/shell.json")
  fs.writeFileSync(shellJson, JSON.stringify({ dock: { position: "left" } }))
  assert.strictEqual(run("--set", "glass=0.85", "--set", "web-glass=0.9", "--set", "snapping=0", "--set", "drop-follow=0", "--set", "blur=15", "--set", "magnification=1.2", "--set", "dock-size=60", "--set", "title-bars=0", "--set", "traffic-lights=18").status, 0)
  assert.deepStrictEqual(status().settings, { glass: 0.85, "web-glass": 0.9, snapping: 0, "drop-follow": 0, blur: 15, "title-bars": 0, "traffic-lights": 18, magnification: 1.2, "dock-size": 60 })
  const look = fs.readFileSync(path.join(themeDir, "look.lua"), "utf8")
  assert.match(look, /o\.window\("\.\*", \{ opacity = "0\.85 0\.85" \}\)/)
  assert.match(look, /brave-browser\|.*", \{ opacity = "0\.9 0\.9" \}\)/)
  assert.match(look, /^local SNAPPING = 0$/m)
  assert.match(look, /^local BLUR = 15$/m)
  assert.match(look, /^local TITLE_BARS = 0$/m)
  assert.match(look, /^local LIGHTS = 18$/m)
  assert.strictEqual(JSON.parse(fs.readFileSync(shellJson, "utf8")).dock.position, "left")
  assert.strictEqual(run("--add", "theme").status, 0)
  assert.deepStrictEqual(status().settings, { glass: 0.85, "web-glass": 0.9, snapping: 0, "drop-follow": 0, blur: 15, "title-bars": 0, "traffic-lights": 18, magnification: 1.2, "dock-size": 60 })
  for (const bad of ["glass=0.2", "glass=2", "magnification=3", "magnification=", "size=1", "glass=1.2.3", "snapping=0.5", "snapping=2", "blur=0.5", "blur=21", "blur=-1", "web-glass=0.1", "dock-size=31", "dock-size=81", "dock-size=50.5", "title-bars=2", "drop-follow=2", "drop-follow=0.5", "traffic-lights=9", "traffic-lights=21", "traffic-lights=14.5"]) {
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
  const before = status().settings
  const removed = run("--remove", "theme")
  assert.strictEqual(removed.status, 0, removed.stdout + removed.stderr)
  assert.strictEqual(status().features.theme, false)
  // Added again, it is as you left it: your settings and wallpapers.
  assert.strictEqual(run("--add", "theme").status, 0)
  assert.deepStrictEqual(status().settings, before)
  assert.ok(fs.existsSync(path.join(themeDir, "backgrounds/mine.jpg")))
  assert.strictEqual(run("--remove", "theme").status, 0)
  const kept = fs.readdirSync(path.join(home, ".config/omarchy/macos-theme-backups"))
  assert.ok(kept.some((d) => fs.existsSync(path.join(home, ".config/omarchy/macos-theme-backups", d, "backgrounds/mine.jpg"))))
  assert.doesNotMatch(fs.readFileSync(path.join(home, ".config/gtk-4.0/gtk.css"), "utf8"), /glass\.css/)

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
  // With a removal in the same run, the widgets change still happens.
  assert.strictEqual(run("--remove", "dock", "--show-widgets", "clock").status, 0)
  assert.deepStrictEqual(status().widgets, ["clock"])

  // The menu bar removed and added again gets back the bar you arranged.
  const arranged = { left: [{ id: "omarchy.workspaces" }], center: [], right: [{ id: "omarchy.clock" }, { id: "omarchy.network" }] }
  fs.writeFileSync(shellJson, JSON.stringify({ bar: { layout: arranged } }))
  fs.mkdirSync(path.join(home, ".config/omarchy/plugins/macos-theme.menubar"), { recursive: true })
  assert.strictEqual(run("--remove", "menubar").status, 0)
  fs.writeFileSync(shellJson, JSON.stringify({ bar: { layout: { left: [], right: [] } } }))
  const back = run("--add", "menubar")
  assert.strictEqual(back.status, 0, back.stderr)
  assert.deepStrictEqual(JSON.parse(fs.readFileSync(shellJson, "utf8")).bar.layout, arranged)

  // Installed again, the menu bar leaves the bar exactly as you arranged it.
  const mine = { left: [{ id: "macos-theme.app-name" }], right: [{ id: "omarchy.clock" }] }
  fs.writeFileSync(shellJson, JSON.stringify({ bar: { layout: mine } }))
  assert.strictEqual(run("--add", "menubar").status, 0)
  assert.deepStrictEqual(JSON.parse(fs.readFileSync(shellJson, "utf8")).bar.layout, mine)

  // Unknown pieces are refused.
  assert.strictEqual(run("--remove", "everything").status, 1)
  assert.strictEqual(run("--add").status, 1)

  // Edits to looknfeel.lua and gtk.css leave no .bak files: snapshots hold the old ones.
  const leftovers = ["hypr", "gtk-4.0"].flatMap((d) => fs.readdirSync(path.join(home, ".config", d)).filter((f) => f.includes(".bak.")))
  assert.deepStrictEqual(leftovers, [])
} finally {
  fs.rmSync(home, { recursive: true, force: true })
}

console.log("install.sh --status --json: ok")
