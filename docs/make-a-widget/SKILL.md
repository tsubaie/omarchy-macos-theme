---
name: make-a-macos-theme-widget
description: Make a desktop widget for the macOS theme for Omarchy (github.com/tsubaie/omarchy-macos-theme), a QML file the theme's widgets plugin shows on the desktop beside its clock, calendar, weather and now playing. Use when asked to make, build or change a desktop widget for this theme.
---

# Make a desktop widget for the macOS theme for Omarchy

The macOS theme shows desktop widgets on frosted glass cards at the top left of the desktop, behind the windows, as macOS does. People can add widgets of their own. This guide is everything an AI agent (or a person) needs to make one that fits.

## What a widget is

A folder in `~/.config/omarchy/macos-theme-widgets/`, named for the widget's id:

```
~/.config/omarchy/macos-theme-widgets/
  uptime/
    Widget.qml      required: the widget itself
    manifest.json   optional: { "name": "Uptime" }, the name shown in menus and in Studio
```

- **The id** is the folder's name: lowercase letters, digits and dashes, starting with a letter or digit (`uptime`, `my-quotes`, `cpu2`). It can't be one of the theme's own: `clock`, `calendar`, `weather`, `playing`.
- **`Widget.qml`** is a Qt Quick file whose root item fills the card. The theme draws the card (its glass, corners and border) around it, so the widget draws only its content.
- **The card** is square, 158 points a side times the shell's scale (`Style.fontScale`), with rounded corners of 22 points. Keep content 14 points from each edge.

Nothing is installed or registered: the theme finds the folder. Once it's there, right-click any widget on the desktop › **Add <name>**, or switch it on in macOS Theme Studio › Widgets. People can drag it like the theme's own.

## What Widget.qml can use

It runs inside Omarchy's shell (Quickshell), so it can import:

- `QtQuick`, `QtQuick.Effects`, `QtQuick.Layouts`
- `Quickshell` (e.g. `SystemClock`), `Quickshell.Io` (`FileView` to read a file, `Process` to run a command), `Quickshell.Services.Mpris` (media), `Quickshell.Services.UPower` (battery), `Quickshell.Hyprland` (workspaces, windows)
- `qs.Commons`: the shell's `Style` (`Style.fontScale`, `Style.reduceMotion`), `Color` and `Util`

Read files and run commands with `FileView` and `Process`, not with `XMLHttpRequest` to `file://`. For the network, `XMLHttpRequest` to `https://` works. Refresh with a `Timer`; once a minute is plenty for most things, and more often costs battery.

## Make it look like the theme

Follow the theme's own widgets, which follow macOS:

| What | Use |
|---|---|
| Sizes | Point sizes times `Style.fontScale`, rounded: `Math.round(13 * Style.fontScale)` |
| Padding | 14 points from the card's edges |
| Main text | White, `Inter`, 13 points; numbers that are the point of the widget in `Inter Display` DemiBold, 34 to 40 points |
| Secondary text | White at 60%: `Qt.rgba(1, 1, 1, 0.6)`, 11 points |
| A small title | Uppercase, 11 points, DemiBold, in one accent color |
| Accent colors | macOS's: red `#ff453a`, blue `#0a84ff`, green `#30d158`, orange `#ff9f0a`, yellow `#ffd60a` |
| Backgrounds | None of its own: the card's frosted glass shows through. A widget that needs one (a picture, a sky) keeps it see-through |
| Motion | Short and gentle; none when `Style.reduceMotion` is true |

Keep it to one glance: one main number or line, a little context under it. No scrollbars, no buttons crowded together; a card is small.

## An example

`docs/make-a-widget/example/uptime/` in the theme's repository is a complete widget: how long since the computer started, read from `/proc/uptime` once a minute. Copy the folder into `~/.config/omarchy/macos-theme-widgets/` to see it, and start from it.

## Check it

- **On the desktop:** right-click a widget › **Add <name>**. Changes to `Widget.qml` show after `omarchy restart shell`.
- **Errors:** a widget that doesn't load says so in its card, and the others carry on. The shell's log names the line: `qs log` (or `./install.sh --doctor` in the theme's folder).
- **Different scales:** it should look right at `Style.fontScale` 1 and 1.5; nothing fixed in pixels.

## Safety

A widget is code that runs inside the shell, with your account's rights: it can read your files and run commands. Only add widgets you made, or whose `Widget.qml` you've read. An AI agent making one should say so, and keep the widget to what it was asked for: no network calls, commands or file reads beyond what the widget shows.

## The prompt

To have an AI agent make one, give it this guide and say what the widget should show, for example:

> Make me a desktop widget for the macOS theme for Omarchy, following https://github.com/tsubaie/omarchy-macos-theme/blob/main/docs/make-a-widget/SKILL.md. It should show: my battery's charge and whether it's charging.
