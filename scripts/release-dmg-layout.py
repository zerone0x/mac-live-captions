"""Builds the release DMG with dmgbuild and checks its Finder layout.

    python3 -I scripts/release-dmg-layout.py build <volume name> <app> <dmg>
    python3 -I scripts/release-dmg-layout.py check <mounted volume>

Run it with a Python that has dmgbuild (scripts/release-dmg.sh makes a
throw-away venv from scripts/release-dmg-requirements.txt). dmgbuild writes
the Finder window settings straight into the image's .DS_Store, so no Finder,
AppleScript or GUI session is involved (docs/DECISIONS.md 0026).

The layout follows electron-builder's default DMG, with the icons centred vertically: a 540 x 380 window with
80-point icons, the app at (130, 175) and an Applications link at (410, 175),
no background image, compressed UDZO. The volume icon is the app's own
AppIcon.icns. `check` reads the .DS_Store of the
mounted image back and fails unless it says exactly that.
"""

import os
import sys

APP = "LiveCaptions.app"
LINK = "Applications"
WINDOW_ORIGIN = (400, 100)
WINDOW_SIZE = (540, 380)
ICON_SIZE = 80
TEXT_SIZE = 12
ICONS = {APP: (130, 175), LINK: (410, 175)}


def fail(message):
    print(f"release-dmg-layout: {message}", file=sys.stderr)
    sys.exit(1)


def build(volume_name, app, dmg):
    import dmgbuild

    if os.path.basename(app.rstrip("/")) != APP:
        fail(f"expected {APP}, got {app}")
    if not os.path.isdir(app):
        fail(f"missing app bundle: {app}")
    if os.path.exists(dmg):
        fail(f"{dmg} already exists")
    icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")
    if not os.path.isfile(icon):
        fail(f"missing {icon} (the volume icon)")
    settings = {
        "format": "UDZO",
        "filesystem": "HFS+",
        "files": [(app, APP)],
        "symlinks": {LINK: "/Applications"},
        "icon_locations": dict(ICONS),
        "window_rect": (WINDOW_ORIGIN, WINDOW_SIZE),
        "default_view": "icon-view",
        "icon_size": float(ICON_SIZE),
        "text_size": float(TEXT_SIZE),
        "background": None,
        "icon": icon,
        "show_status_bar": False,
        "show_tab_view": False,
        "show_toolbar": False,
        "show_pathbar": False,
        "show_sidebar": False,
    }
    # Raises (and so exits non-zero) when an hdiutil step fails.
    dmgbuild.build_dmg(dmg, volume_name, settings=settings)
    if not os.path.isfile(dmg) or os.path.getsize(dmg) == 0:
        fail(f"dmgbuild did not write {dmg}")
    print(f"release-dmg-layout: built {dmg}")


def check(volume):
    from ds_store import DSStore

    path = os.path.join(volume, ".DS_Store")
    if not os.path.isfile(path):
        fail(f"no .DS_Store in {volume}: the window layout is missing")
    with DSStore.open(path, "r") as store:
        try:
            bwsp = store["."]["bwsp"]
            icvp = store["."]["icvp"]
            locations = {name: tuple(store[name]["Iloc"]) for name in ICONS}
        except KeyError as error:
            fail(f".DS_Store lacks {error}")
    (x, y), (w, h) = WINDOW_ORIGIN, WINDOW_SIZE
    want_bounds = f"{{{{{x}, {y}}}, {{{w}, {h}}}}}"
    if bwsp.get("WindowBounds") != want_bounds:
        fail(f"window bounds {bwsp.get('WindowBounds')!r}, expected {want_bounds!r}")
    for key in ("ShowToolbar", "ShowSidebar", "ShowStatusBar", "ShowPathbar"):
        if bwsp.get(key) is not False:
            fail(f"{key} is {bwsp.get(key)!r}, expected False")
    if icvp.get("iconSize") != float(ICON_SIZE):
        fail(f"icon size {icvp.get('iconSize')!r}, expected {ICON_SIZE}")
    if icvp.get("textSize") != float(TEXT_SIZE):
        fail(f"text size {icvp.get('textSize')!r}, expected {TEXT_SIZE}")
    if icvp.get("arrangeBy") != "none":
        fail(f"icons are arranged by {icvp.get('arrangeBy')!r}, expected free placement")
    if icvp.get("backgroundType") != 0:
        fail(f"background type {icvp.get('backgroundType')!r}, expected none (0)")
    for name, want in ICONS.items():
        if locations[name] != want:
            fail(f"{name} is at {locations[name]}, expected {want}")
    print(
        f"release-dmg-layout: OK ({w}x{h} window, {ICON_SIZE}pt icons, "
        + ", ".join(f"{name} at {pos}" for name, pos in ICONS.items())
        + ")"
    )


def main(argv):
    if len(argv) == 5 and argv[1] == "build":
        build(argv[2], argv[3], argv[4])
    elif len(argv) == 3 and argv[1] == "check":
        check(argv[2])
    else:
        fail("usage: release-dmg-layout.py build <volume name> <app> <dmg> | check <mounted volume>")


if __name__ == "__main__":
    main(sys.argv)
