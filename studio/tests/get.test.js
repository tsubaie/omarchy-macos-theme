// get.sh installs a release tarball, packed by package.sh as the release is,
// into ~/.local/bin with a launcher entry pointing at it.
// Run with: node tests/get.test.js
const assert = require("assert")
const { spawnSync } = require("child_process")
const fs = require("fs")
const os = require("os")
const path = require("path")

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "studio-get-"))
try {
  const binary = path.join(tmp, "omarchy-macos-studio")
  fs.writeFileSync(binary, "#!/bin/sh\n", { mode: 0o755 })
  const pack = spawnSync("bash", [path.join(__dirname, "../package.sh"), binary, "test", path.join(tmp, "dist")], { encoding: "utf8" })
  assert.strictEqual(pack.status, 0, pack.stderr)
  const tarball = path.join(tmp, "dist/omarchy-macos-studio-test.tar.gz")

  const home = path.join(tmp, "home")
  const r = spawnSync("bash", [path.join(__dirname, "../get.sh")], {
    env: { ...process.env, HOME: home, XDG_DATA_HOME: "", XDG_BIN_HOME: "", OMARCHY_MACOS_STUDIO_URL: `file://${tarball}` },
    encoding: "utf8",
  })
  // The releases are x86_64 and aarch64, on Arch only; elsewhere get.sh refuses, as it should.
  if (!["x64", "arm64"].includes(os.arch()) || spawnSync("sh", ["-c", "command -v pacman"]).status !== 0) {
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
