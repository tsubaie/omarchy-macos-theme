// get.sh installs a release tarball, laid out as the release job packs it,
// into ~/.local/bin with a launcher entry pointing at it.
// Run with: node tests/get.test.js
const assert = require("assert")
const { spawnSync } = require("child_process")
const fs = require("fs")
const os = require("os")
const path = require("path")

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "studio-get-"))
try {
  const pkg = path.join(tmp, "dist/omarchy-macos-studio")
  fs.mkdirSync(path.join(pkg, "assets"), { recursive: true })
  fs.writeFileSync(path.join(pkg, "omarchy-macos-studio"), "#!/bin/sh\n", { mode: 0o755 })
  fs.copyFileSync(path.join(__dirname, "../install-desktop.sh"), path.join(pkg, "install-desktop.sh"))
  fs.chmodSync(path.join(pkg, "install-desktop.sh"), 0o755)
  fs.copyFileSync(path.join(__dirname, "../assets/icon-omarchy.svg"), path.join(pkg, "assets/icon-omarchy.svg"))
  const tarball = path.join(tmp, "studio.tar.gz")
  assert.strictEqual(spawnSync("tar", ["-czf", tarball, "-C", path.join(tmp, "dist"), "omarchy-macos-studio"]).status, 0)

  const home = path.join(tmp, "home")
  const r = spawnSync("bash", [path.join(__dirname, "../get.sh")], {
    env: { ...process.env, HOME: home, XDG_DATA_HOME: "", XDG_BIN_HOME: "", OMARCHY_MACOS_STUDIO_URL: `file://${tarball}` },
    encoding: "utf8",
  })
  // The release is x86_64 and Arch only; elsewhere get.sh refuses, as it should.
  if (os.arch() !== "x64" || spawnSync("sh", ["-c", "command -v pacman"]).status !== 0) {
    assert.notStrictEqual(r.status, 0)
  } else {
    assert.strictEqual(r.status, 0, r.stderr)
    const bin = path.join(home, ".local/bin/omarchy-macos-studio")
    assert.ok(fs.statSync(bin).mode & 0o111)
    const entry = fs.readFileSync(path.join(home, ".local/share/applications/omarchy-macos-studio.desktop"), "utf8")
    assert.ok(entry.includes(`Exec="${bin}"`), entry)
    assert.ok(fs.existsSync(path.join(home, ".local/share/icons/hicolor/scalable/apps/omarchy-macos-studio.svg")))
  }
} finally {
  fs.rmSync(tmp, { recursive: true, force: true })
}

console.log("get: ok")
