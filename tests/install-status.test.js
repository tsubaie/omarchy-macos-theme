// install.sh --add, --remove and --status --json, in a throwaway home with a fake
// omarchy command. Run with: node tests/install-status.test.js
const assert = require("assert")
const { execFileSync, spawn, spawnSync } = require("child_process")
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
// Hyprland's workspaces, as $HOME/workspaces.json says; every other call succeeds quietly.
fs.writeFileSync(path.join(bin, "hyprctl"), '#!/bin/sh\n[ "$1" = workspaces ] && cat "$HOME/workspaces.json" 2>/dev/null\nexit 0\n', { mode: 0o755 })

const env = { ...process.env, DBUS_SESSION_BUS_ADDRESS: "", HYPRLAND_INSTANCE_SIGNATURE: "", XDG_RUNTIME_DIR: home, HOME: home, XDG_CONFIG_HOME: path.join(home, ".config"), PATH: `${bin}:${process.env.PATH}`, THEME: "Tokyo Night", USER: "me" }
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
  assert.deepStrictEqual(s.settings, { glass: 0.85, "web-glass": 1, snapping: 1, "drop-follow": 1, blur: 10, "title-bars": 1, "traffic-lights": 14, "reduce-motion": 0, magnification: 1.75, "dock-size": 48, "dock-previews": 1 })

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
  // a killed run's lock is taken over, also when its pid now belongs to another program.
  const backups = path.join(home, ".config/omarchy/macos-theme-backups")
  const lock = path.join(backups, ".lock")
  fs.mkdirSync(lock)
  const other = spawn("sleep", ["30"], { argv0: "install.sh" })
  fs.writeFileSync(path.join(lock, "pid"), String(other.pid))
  const busy = run("--add", "switcher")
  other.kill()
  assert.strictEqual(busy.status, 1)
  assert.match(busy.stderr, /Another run of install\.sh/)
  assert.strictEqual(status().features.switcher, false)
  for (const dead of ["999999999", String(process.pid)]) {
    fs.mkdirSync(lock, { recursive: true })
    fs.writeFileSync(path.join(lock, "pid"), dead)
    assert.strictEqual(run("--add", "switcher").status, 0, dead)
    assert.ok(!fs.existsSync(lock))
  }
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
  fs.writeFileSync(gtkCss, '/* macOS theme: blur behind see-through GTK windows. Added by omarchy-macos-theme. */\n@import url("file:///usr/share/omarchy/default/gtk/glass.css");\n')
  assert.strictEqual(run("--add", "theme").status, 0)
  const gtk = fs.readFileSync(gtkCss, "utf8")
  assert.match(gtk, /current\/theme\/glass\.css/)
  assert.doesNotMatch(gtk, /default\/gtk\/glass\.css/)

  // Settings: glass goes into look.lua and stays through a reinstall; magnification
  // goes into the dock's section of shell.json, next to what was there.
  const shellJson = path.join(home, ".config/omarchy/shell.json")
  fs.writeFileSync(shellJson, JSON.stringify({ dock: { position: "left" } }))
  assert.strictEqual(run("--set", "glass=0.9", "--set", "web-glass=0.9", "--set", "snapping=0", "--set", "drop-follow=0", "--set", "blur=15", "--set", "magnification=1.2", "--set", "dock-size=60", "--set", "dock-previews=0", "--set", "title-bars=0", "--set", "traffic-lights=18", "--set", "reduce-motion=1").status, 0)
  assert.deepStrictEqual(status().settings, { glass: 0.9, "web-glass": 0.9, snapping: 0, "drop-follow": 0, blur: 15, "title-bars": 0, "traffic-lights": 18, "reduce-motion": 1, magnification: 1.2, "dock-size": 60, "dock-previews": 0 })
  const look = fs.readFileSync(path.join(themeDir, "look.lua"), "utf8")
  // Glass is for the windows you aren't using: the active one stays solid.
  assert.match(look, /o\.window\("\.\*", \{ opacity = "1 0\.9" \}\)/)
  // The shell's panels, menus, launcher and notifications take the same glass.
  const shellToml = fs.readFileSync(path.join(themeDir, "shell.toml"), "utf8")
  for (const section of ["popups", "launcher", "menu", "notifications"])
    assert.match(shellToml, new RegExp(`^\\[${section}\\][^]*?^background-alpha *= *0\\.9$`, "m"), section)
  assert.match(look, /brave-browser\|.*", \{ opacity = "0\.9 0\.9" \}\)/)
  assert.match(look, /^local SNAPPING = 0$/m)
  assert.match(look, /^local BLUR = 15$/m)
  assert.match(look, /^local TITLE_BARS = 0$/m)
  assert.match(look, /^local LIGHTS = 18$/m)
  assert.match(look, /^local REDUCE_MOTION = 1$/m)
  assert.strictEqual(JSON.parse(fs.readFileSync(shellJson, "utf8")).dock.position, "left")
  assert.strictEqual(run("--add", "theme").status, 0)
  assert.deepStrictEqual(status().settings, { glass: 0.9, "web-glass": 0.9, snapping: 0, "drop-follow": 0, blur: 15, "title-bars": 0, "traffic-lights": 18, "reduce-motion": 1, magnification: 1.2, "dock-size": 60, "dock-previews": 0 })
  // A look.lua from before (the same glass for every window, as low as 0.5) is
  // kept through a reinstall in the new form, raised to the least glass now takes.
  const lookPath = path.join(themeDir, "look.lua")
  fs.writeFileSync(lookPath, fs.readFileSync(lookPath, "utf8").replace('opacity = "1 0.9"', 'opacity = "0.7 0.7"'))
  assert.strictEqual(status().settings.glass, 0.7)
  assert.strictEqual(run("--add", "theme").status, 0)
  assert.strictEqual(status().settings.glass, 0.75)
  assert.match(fs.readFileSync(lookPath, "utf8"), /o\.window\("\.\*", \{ opacity = "1 0\.75" \}\)/)
  assert.strictEqual(run("--set", "glass=0.9").status, 0)
  for (const bad of ["glass=0.2", "glass=0.7","glass=2", "magnification=3", "magnification=", "size=1", "glass=1.2.3", "snapping=0.5", "snapping=2", "blur=0.5", "blur=21", "blur=-1", "web-glass=0.1", "dock-size=31", "dock-size=81", "dock-size=50.5", "title-bars=2", "drop-follow=2", "drop-follow=0.5", "traffic-lights=9", "traffic-lights=21", "traffic-lights=14.5", "reduce-motion=2", "reduce-motion=0.5", "dock-previews=2", "dock-previews=0.5"]) {
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

  // Removing the theme while it is current switches first to the theme you
  // had before it; with none recorded, Tokyo Night, which Omarchy ships with.
  fs.mkdirSync(themeDir, { recursive: true })
  fs.rmSync(path.join(home, "current"), { force: true })
  env.THEME = "Macos"
  s = status()
  assert.strictEqual(s.active, true)
  assert.strictEqual(s.features.theme, true)
  assert.strictEqual(s["previous-theme"], "Tokyo Night")
  const switched = run("--remove", "theme")
  assert.strictEqual(switched.status, 0, switched.stderr)
  assert.strictEqual(fs.readFileSync(path.join(home, "current"), "utf8").trim(), "Tokyo Night")
  assert.strictEqual(status().features.theme, false)

  // Removing all of it while it is current switches to the theme named first, one that exists.
  fs.mkdirSync(themeDir, { recursive: true })
  fs.rmSync(path.join(home, "current"), { force: true })
  assert.strictEqual(run("--switch-to", "Nope", "--uninstall").status, 1)
  assert.strictEqual(status().features.theme, true)
  const all = run("--switch-to", "Tokyo Night", "--uninstall")
  assert.strictEqual(all.status, 0, all.stderr)
  assert.match(all.stdout, /what it replaced is back/)
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

  // Widgets of your own: listed by their folder's name with their manifest's
  // name; shown like the theme's own; a folder without a Widget.qml, one
  // named like the theme's own, or a name that's no safe id isn't one.
  const own = path.join(home, ".config/omarchy/macos-theme-widgets")
  for (const dir of ["uptime", "my-quotes", "clock", "no-widget", "Bad Name"]) fs.mkdirSync(path.join(own, dir), { recursive: true })
  for (const dir of ["uptime", "my-quotes", "clock", "Bad Name"]) fs.writeFileSync(path.join(own, dir, "Widget.qml"), "")
  fs.writeFileSync(path.join(own, "my-quotes/manifest.json"), JSON.stringify({ name: "Quotes" }))
  assert.deepStrictEqual(status()["custom-widgets"], [{ id: "my-quotes", name: "Quotes" }, { id: "uptime", name: "uptime" }])
  const ownShown = run("--show-widgets", "clock,uptime")
  assert.strictEqual(ownShown.status, 0, ownShown.stderr)
  assert.deepStrictEqual(status().widgets, ["clock", "uptime"])
  for (const bad of ["clock,no-widget", "clock,Bad Name", "clock,../uptime"]) assert.strictEqual(run("--show-widgets", bad).status, 1, bad)
  // Which workspaces show them: all by default, then only the named ones, then
  // all again, without touching the widgets shown; bad lists refused.
  assert.strictEqual(status()["widget-workspaces"], "all")
  const some = run("--widget-workspaces", "1,3")
  assert.strictEqual(some.status, 0, some.stderr)
  assert.deepStrictEqual(status()["widget-workspaces"], [1, 3])
  assert.deepStrictEqual(status().widgets, ["clock", "uptime"])
  assert.strictEqual(run("--widget-workspaces", "all").status, 0)
  assert.strictEqual(status()["widget-workspaces"], "all")
  assert.strictEqual(JSON.parse(fs.readFileSync(shellJson, "utf8")).widgets.workspaces, undefined)
  for (const bad of ["", "0", "1,", "1;2", "one", "-1"]) assert.strictEqual(run("--widget-workspaces", bad).status, 1, bad)
  // The ones to choose from: Hyprland's, on the widgets' screen when one is named.
  assert.deepStrictEqual(status()["widget-workspaces-there"], [])
  fs.writeFileSync(path.join(home, "workspaces.json"), JSON.stringify([
    { id: 4, monitor: "DP-2" }, { id: 1, monitor: "DP-2" }, { id: 5, monitor: "HDMI-A-1" }, { id: -98, monitor: "DP-2" }]))
  assert.deepStrictEqual(status()["widget-workspaces-there"], [1, 4, 5])
  const withScreen = JSON.parse(fs.readFileSync(shellJson, "utf8"))
  withScreen.widgets.screen = "HDMI-A-1"
  fs.writeFileSync(shellJson, JSON.stringify(withScreen))
  assert.deepStrictEqual(status()["widget-workspaces-there"], [5])
  fs.rmSync(path.join(home, "workspaces.json"))
  // Its folder gone, it's no longer shown; the theme's own stay.
  fs.rmSync(path.join(own, "uptime"), { recursive: true })
  assert.deepStrictEqual(status().widgets, ["clock"])
  fs.rmSync(own, { recursive: true })

  // An update whose menu bar part Omarchy won't enable takes the whole menu bar out, and
  // puts the bar back as it was before it: Network back out of the tray drawer.
  const unbarred = { left: [{ id: "omarchy.workspaces" }], right: [{ id: "omarchy.network" }] }
  fs.writeFileSync(shellJson, JSON.stringify({ bar: { layout: unbarred } }))
  assert.strictEqual(run("--add", "menubar").status, 0)
  fs.writeFileSync(shellJson, JSON.stringify({ bar: { layout: { left: [{ id: "omarchy.workspaces" }], right: [{ id: "macos-theme.control-center" }], tray: [{ id: "omarchy.network" }] } } }))
  const halfBar = spawnSync("bash", [script, "--add", "menubar"], { env: { ...env, FAIL_ENABLE: "macos-theme.control-center" }, encoding: "utf8" })
  assert.strictEqual(halfBar.status, 1)
  assert.match(halfBar.stderr, /Could not install macos-theme\.control-center/)
  assert.strictEqual(status().features.menubar, false)
  assert.ok(!fs.existsSync(path.join(home, ".config/omarchy/plugins/macos-theme.app-name")))
  const afterHalf = JSON.parse(fs.readFileSync(shellJson, "utf8")).bar.layout
  assert.deepStrictEqual(afterHalf.right, [{ id: "omarchy.network" }])
  assert.deepStrictEqual(afterHalf.tray ?? [], [])
  // A first install that fails leaves the bar and the arrangement that removal remembered,
  // so adding it again brings that arrangement back.
  const remembered = { left: [{ id: "omarchy.workspaces" }], right: [{ id: "macos-theme.control-center" }], tray: [{ id: "omarchy.network" }] }
  const firstTry = spawnSync("bash", [script, "--add", "menubar"], { env: { ...env, FAIL_ENABLE: "macos-theme.app-name" }, encoding: "utf8" })
  assert.strictEqual(firstTry.status, 1)
  assert.strictEqual(status().features.menubar, false)
  assert.deepStrictEqual(JSON.parse(fs.readFileSync(shellJson, "utf8")).bar.layout, afterHalf)
  assert.strictEqual(run("--add", "menubar").status, 0)
  assert.deepStrictEqual(JSON.parse(fs.readFileSync(shellJson, "utf8")).bar.layout, remembered)

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
