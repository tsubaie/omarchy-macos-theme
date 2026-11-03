// Updating the theme as people have it: install an older version into a
// throwaway home, then update the way Studio's Update does (every installed
// piece added again by the new install.sh), and check nothing is lost. Then
// restore a snapshot the older version took. UPGRADE_FROM picks the older
// commit; by default one from before the theme marked its own clones.
// Run with: node tests/upgrade.test.js
const assert = require("assert")
const { spawnSync } = require("child_process")
const fs = require("fs")
const os = require("os")
const path = require("path")

const repo = path.join(__dirname, "..")
const from = process.env.UPGRADE_FROM || "3b32042"
const user = "someone"
if (spawnSync("git", ["-C", repo, "cat-file", "-e", `${from}^{commit}`]).status !== 0) {
  console.log(`upgrade: skipped (no commit ${from} here; a shallow clone?)`)
  process.exit(0)
}

const home = fs.mkdtempSync(path.join(os.tmpdir(), "macos-theme-upgrade-"))
const old = path.join(home, "old")
fs.mkdirSync(old)
spawnSync("sh", ["-c", `git -C "${repo}" archive ${from} | tar -x -C "${old}"`])
const bin = path.join(home, "bin")
fs.mkdirSync(bin)
// Clones named after you, reported as Omarchy reports them, which older
// versions read; every other call succeeds quietly.
fs.writeFileSync(path.join(bin, "omarchy"), `#!/bin/sh
[ "$1 $2" = "theme current" ] && echo Other
[ "$1 $2" = "theme list" ] && printf 'Macos\\nOther\\n'
if [ "$1 $2" = "plugin clone" ]; then
  dir="$XDG_CONFIG_HOME/omarchy/plugins/$USER.\${3#omarchy.}"
  [ -e "$dir" ] && exit 1
  mkdir -p "$dir" && touch "$dir/Menu.qml" "$dir/Workspaces.qml"
  # This Omarchy's own file where there is one, so the patches really run.
  case $3 in omarchy.menu) src=menu/Menu.qml ;; omarchy.workspaces) src=bar/widgets/Workspaces.qml ;; *) src= ;; esac
  real="\${OMARCHY_PATH:-/usr/share/omarchy}/shell/plugins/$src"
  [ -n "$src" ] && [ -f "$real" ] && cp "$real" "$dir/"
  printf '{ "omarchy": { "clonedFrom": "%s" } }' "$3" > "$dir/manifest.json"
  echo "Cloned $3 to $dir and switched to $USER.\${3#omarchy.}"
fi
exit 0
`, { mode: 0o755 })
for (const quiet of ["hyprctl", "omarchy-shell", "qs"]) fs.writeFileSync(path.join(bin, quiet), "#!/bin/sh\nexit 0\n", { mode: 0o755 })
fs.writeFileSync(path.join(bin, "fc-list"), "#!/bin/sh\necho Inter\n", { mode: 0o755 })
const env = { ...process.env, HOME: home, USER: user, XDG_CONFIG_HOME: path.join(home, ".config"), PATH: `${bin}:${process.env.PATH}` }
delete env.MACOS_THEME_NO_SNAPSHOT
// Without Omarchy (CI), the one file of it installers read: its default shell.json.
if (!fs.existsSync(path.join(env.OMARCHY_PATH || "/usr/share/omarchy", "config/omarchy/shell.json"))) {
  env.OMARCHY_PATH = path.join(home, "omarchy")
  fs.mkdirSync(path.join(env.OMARCHY_PATH, "config/omarchy"), { recursive: true })
  fs.writeFileSync(path.join(env.OMARCHY_PATH, "config/omarchy/shell.json"), "{}")
}
const run = (dir, ...args) => {
  const r = spawnSync("bash", [path.join(dir, "install.sh"), ...args], { env, encoding: "utf8" })
  assert.strictEqual(r.status, 0, `${dir === old ? from : "now"} install.sh ${args.join(" ")}:\n${r.stdout}${r.stderr}`)
  return r
}
const status = (dir) => JSON.parse(run(dir, "--status", "--json").stdout)
const config = (p) => path.join(home, ".config", p)

try {
  // Everything that installs offline, with settings and a wallpaper of yours.
  const pieces = ["theme", "rows", "wide-menu", "dock", "switcher", "osd", "dictation-hud", "menubar", "bar-icons", "lock", "widgets"]
  run(old, ...pieces.flatMap((p) => ["--add", p]), "--set", "glass=0.85", "--set", "magnification=1.3")
  fs.writeFileSync(config("omarchy/themes/macos/backgrounds/mine.jpg"), "photo")
  const before = status(old)
  // The wide menu counts only once its patch took, which needs Omarchy's menu.
  for (const p of pieces.filter((p) => p !== "wide-menu")) assert.strictEqual(before.features[p], true, `${from} didn't install ${p}`)
  run(old, "--backup")
  const oldSnapshot = JSON.parse(run(old, "--backups", "--json").stdout)[0].id

  // Studio's Update: the installed pieces, added again by the new installer.
  const installed = Object.keys(before.features).filter((p) => before.features[p] && p !== "icons")
  run(repo, ...installed.flatMap((p) => ["--add", p]))
  const after = status(repo)
  assert.deepStrictEqual(after.features, before.features, "an update changed what is installed")
  // Each setting the older version had keeps its value; a setting new since then starts at its default.
  for (const key of Object.keys(before.settings)) assert.strictEqual(after.settings[key], before.settings[key], `an update changed your ${key} setting`)
  assert.strictEqual(fs.readFileSync(config("omarchy/themes/macos/backgrounds/mine.jpg"), "utf8"), "photo")
  // The older version's clones are known as the theme's, and marked now.
  for (const name of before.features["wide-menu"] ? ["menu", "lock"] : ["lock"]) {
    assert.ok(fs.existsSync(config(`omarchy/plugins/${user}.${name}/.macos-theme`)), `${user}.${name} isn't marked as the theme's`)
  }

  // A snapshot the older version took of all of it restores with the new one.
  run(repo, "--uninstall")
  run(repo, "--restore", oldSnapshot)
  const restored = status(repo)
  assert.deepStrictEqual(restored.features, before.features, "restoring the older snapshot")
  for (const key of Object.keys(before.settings)) assert.strictEqual(restored.settings[key], before.settings[key], `the restore changed your ${key} setting`)
  // And everything comes off again.
  run(repo, "--uninstall")
  const gone = status(repo)
  assert.ok(Object.values(gone.features).every((on) => !on), JSON.stringify(gone.features))
} finally {
  fs.rmSync(home, { recursive: true, force: true })
}

console.log(`upgrade from ${from}: ok`)
