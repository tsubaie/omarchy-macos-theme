#!/usr/bin/perl -0pi
# Patches a clone of Omarchy's Menu.qml into the macOS theme's launcher:
# wider, a magnifying glass before the search text, and "Search" instead of
# "Go". Each change is skipped when already applied, so it is safe to re-run.
# Usage: perl -0pi menu-patch.pl path/to/Menu.qml

unless (/macOS theme: wider/) {
  s/\? Style\.space\(520\) : Style\.space\(300\)\), panel\.width/? Style.space(640) : Style.space(560)), panel.width/;
  s/^(  )property int cardWidth: /$1\/\/ macOS theme: wider, closer to Spotlight (Omarchy uses 300 and 520).\n$1property int cardWidth: /m;
}

unless (/id: searchGlass/) {
  s/(\n( +)FilterInput \{\n +id: filterInput\n +)anchors\.left: parent\.left\n/
    "\n$2\/\/ macOS theme: Spotlight's magnifying glass before the search text.\n" .
    "$2Text {\n$2  id: searchGlass\n$2  anchors.left: parent.left\n$2  anchors.verticalCenter: parent.verticalCenter\n" .
    "$2  textFormat: Text.PlainText\n$2  text: \"\\uf002\"\n$2  color: root.foreground\n$2  opacity: 0.6\n" .
    "$2  font.family: \"JetBrainsMono Nerd Font\"\n$2  font.pixelSize: Style.font.heading\n$2}\n\n" .
    substr($1, 1) . "anchors.left: searchGlass.right\n$2  anchors.leftMargin: Style.space(10)\n"/e;
}

unless (/macOS theme: the root heading/) {
  s/^(\s+)var mergedMenu = MenuModel\.mergeMenuSources\(translatedDefaults, root\.userMenuItems, rootCatalog && rootCatalog\.label\)/$1\/\/ macOS theme: the root heading reads "Search", as in Spotlight.\n$1var mergedMenu = MenuModel.mergeMenuSources(translatedDefaults, root.userMenuItems, "Search")/m;
  s/: "Go"\) \+ "…"\)/: "Search") + "…")/;
}
