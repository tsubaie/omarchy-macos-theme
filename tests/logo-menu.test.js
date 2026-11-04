// The logo menu: its items and their order, the logos, and Force Quit's
// list of apps. Run with: node tests/logo-menu.test.js
const assert = require("assert")
const m = require("../plugins/macos-theme.logo-menu/LogoModel.js")

// As macOS's Apple menu: About first, then Settings and the store, Force Quit
// alone, sleep and power, then lock and log out, groups split by lines.
assert.deepStrictEqual(m.ITEMS.map((i) => (i ? i.id : "—")),
  ["about", "—", "settings", "store", "—", "forcequit", "—", "sleep", "restart", "shutdown", "—", "lock", "logout"])
assert.deepStrictEqual(m.choosable().map((i) => i.id), ["about", "settings", "store", "forcequit", "sleep", "restart", "shutdown", "lock", "logout"])
// System Settings opens Omarchy's launcher; the risky ones ask first.
assert.match(m.ITEMS.find((i) => i && i.id === "settings").run, /omarchy\.menu/)
for (const id of ["restart", "shutdown", "logout"]) assert.ok(m.ITEMS.find((i) => i && i.id === id).ask, id)
for (const id of ["sleep", "lock", "settings"]) assert.ok(!m.ITEMS.find((i) => i && i.id === id).ask, id)
assert.strictEqual(m.ITEMS.find((i) => i && i.id === "forcequit").altLabel, "Force Quit Applications…")

// The logos: Omarchy's mark first and by default; an unknown name is it too.
assert.strictEqual(m.LOGOS[0].id, "omarchy")
assert.strictEqual(m.logo("arch").id, "arch")
assert.strictEqual(m.logo("apple").id, "omarchy")
assert.strictEqual(m.logo(undefined).id, "omarchy")
// install.sh --set logo= takes exactly these names.
const installSh = require("fs").readFileSync(require("path").join(__dirname, "..", "install.sh"), "utf8")
assert.deepStrictEqual(/^LOGOS="([^"]*)"/m.exec(installSh)[1].split(" "), m.LOGOS.map((l) => l.id))
// Studio's Menu Bar page offers the same ones.
const studioQml = require("fs").readFileSync(require("path").join(__dirname, "..", "studio", "qml", "Main.qml"), "utf8")
assert.deepStrictEqual([...studioQml.matchAll(/\{ id: "(\w+)", name: "[^"]+", glyph: /g)].map((x) => x[1]), m.LOGOS.map((l) => l.id))

// Force Quit's list: one per app, last used first, with all its windows and
// processes; never the shell, its bar, Hyprland, or a window with no process.
const apps = m.apps([
  { class: "firefox", title: "Docs", address: "0x1", pid: 100, focusHistoryID: 2 },
  { class: "firefox", title: "Mail", address: "0x2", pid: 100, focusHistoryID: 3 },
  { class: "org.gnome.Nautilus", title: "Home", address: "0x3", pid: 200, focusHistoryID: 0 },
  { class: "quickshell", title: "bar", address: "0x4", pid: 300, focusHistoryID: 1 },
  { class: "kitty", title: "shell", address: "0x5", pid: 400, focusHistoryID: 4 },
  { class: "ghost", title: "x", address: "0x6", pid: 0, focusHistoryID: 5 },
  { class: "", title: "untitled", address: "0x7", pid: 500, focusHistoryID: 6 },
], 400)
assert.deepStrictEqual(apps.map((a) => a.id), ["org.gnome.Nautilus", "firefox"])
assert.deepStrictEqual(apps[1], { id: "firefox", name: "Firefox", addresses: ["0x1", "0x2"], pids: [100] })
assert.strictEqual(apps[0].name, "Nautilus")
assert.deepStrictEqual(m.apps(null), [])

// Force Quit by Clicking: the window on top at the point, on a shown workspace.
const mons = [{ activeWorkspace: { id: 1 }, specialWorkspace: { id: 0 } }, { activeWorkspace: { id: 2 }, specialWorkspace: { id: -98 } }]
const win = (o) => Object.assign({ mapped: true, hidden: false, pid: 10, class: "app", at: [0, 0], size: [100, 100], workspace: { id: 1 }, floating: false, fullscreen: 0, focusHistoryID: 5 }, o)
const wins = [
  win({ address: "tiled" }),
  win({ address: "float", floating: true, at: [50, 50], size: [100, 100], focusHistoryID: 9 }),
  win({ address: "other-ws", workspace: { id: 3 } }),
  win({ address: "shell", class: "quickshell", at: [60, 60], size: [10, 10], floating: true, focusHistoryID: 0 }),
  win({ address: "right", workspace: { id: 2 }, at: [2000, 0], size: [500, 500] }),
  win({ address: "scratch", workspace: { id: -98 }, at: [2100, 100], size: [50, 50], focusHistoryID: 20 }),
]
assert.strictEqual(m.windowAt(wins, mons, 10, 10).address, "tiled")
assert.strictEqual(m.windowAt(wins, mons, 60, 60).address, "float")
assert.strictEqual(m.windowAt(wins, mons, 2010, 10).address, "right")
assert.strictEqual(m.windowAt(wins, mons, 2110, 110).address, "scratch")
assert.strictEqual(m.windowAt(wins, mons, 500, 500), null)
assert.strictEqual(m.windowAt(null, null, 0, 0), null)

// About's names, as About This Mac gives them.
assert.strictEqual(m.chipName("AMD Ryzen 9 8945HX with Radeon Graphics"), "AMD Ryzen 9 8945HX")
assert.strictEqual(m.chipName("Intel(R) Core(TM) i7-1260P"), "Intel Core i7-1260P")
assert.strictEqual(m.chipName("11th Gen Intel(R) Core(TM) i7-1165G7 @ 2.80GHz CPU"), "11th Gen Intel Core i7-1165G7 @ 2.80GHz")
assert.strictEqual(m.chipName("AMD Ryzen 7 5800X 8-Core Processor"), "AMD Ryzen 7 5800X")
assert.strictEqual(m.gpuName("NVIDIA Corporation GB206 [GeForce RTX 5060] (rev a1)"), "NVIDIA GeForce RTX 5060")
assert.strictEqual(m.gpuName("Intel Corporation Raptor Lake-P [Iris Xe Graphics] (rev 04)"), "Intel Iris Xe Graphics")
assert.strictEqual(m.gpuName("Advanced Micro Devices, Inc. [AMD/ATI] Phoenix1 (rev c5)"), "Advanced Micro Devices, Inc. [AMD/ATI] Phoenix1")
assert.strictEqual(m.gpuName(""), "")

console.log("logo menu: ok")
