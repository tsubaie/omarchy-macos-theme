// install-desktop.sh writes an Exec= line a launcher reads back as the same
// paths, even with spaces, $ and % in them, as the Desktop Entry spec quotes
// them. Run with: node tests/install-desktop.test.js
const assert = require("assert")
const { spawnSync } = require("child_process")
const fs = require("fs")
const os = require("os")
const path = require("path")

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "studio-desktop-"))
try {
  // The app in a folder whose path has a space, a $ and a %, as a checkout might.
  const app = path.join(tmp, "my $apps 100%", "studio")
  fs.mkdirSync(path.join(app, "target/release"), { recursive: true })
  fs.mkdirSync(path.join(app, "assets"))
  fs.copyFileSync(path.join(__dirname, "../install-desktop.sh"), path.join(app, "install-desktop.sh"))
  fs.copyFileSync(path.join(__dirname, "../assets/icon-omarchy.svg"), path.join(app, "assets/icon-omarchy.svg"))
  const binary = path.join(app, "target/release/omarchy-macos-studio")
  fs.writeFileSync(binary, "#!/bin/sh\n", { mode: 0o755 })
  const theme = path.join(tmp, "the \"theme\"")
  fs.mkdirSync(theme)
  fs.writeFileSync(path.join(theme, "install.sh"), "")

  const data = path.join(tmp, "data")
  const r = spawnSync("bash", [path.join(app, "install-desktop.sh"), theme], {
    env: { ...process.env, XDG_DATA_HOME: data }, encoding: "utf8",
  })
  assert.strictEqual(r.status, 0, r.stderr)
  const entry = fs.readFileSync(path.join(data, "applications/omarchy-macos-studio.desktop"), "utf8")
  const exec = entry.split("\n").find((l) => l.startsWith("Exec=")).slice(5)

  // Read back as a launcher does: the file's escapes first, then the quoted
  // arguments, then %% as %.
  const unescaped = exec.replace(/\\(.)/g, (_, c) => (c === "\\" ? "\\" : "\\" + c))
  const args = [...unescaped.matchAll(/"((?:[^"\\]|\\.)*)"|(\S+)/g)]
    .map((m) => (m[1] !== undefined ? m[1].replace(/\\(["`$\\])/g, "$1") : m[2]).replace(/%%/g, "%"))
  assert.deepStrictEqual(args, ["env", `OMARCHY_MACOS_THEME_DIR=${theme}`, binary])

  const validate = spawnSync("desktop-file-validate", [path.join(data, "applications/omarchy-macos-studio.desktop")], { encoding: "utf8" })
  if (validate.error === undefined) assert.strictEqual(validate.status, 0, validate.stdout + validate.stderr)
} finally {
  fs.rmSync(tmp, { recursive: true, force: true })
}

console.log("install-desktop: ok")
