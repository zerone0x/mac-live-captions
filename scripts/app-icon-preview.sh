#!/usr/bin/env bash
# Pictures of the app icon as the built app ships it (docs/DECISIONS.md 0025),
# for review in the CI artifact:
#   iconset/           every size, extracted from Contents/Resources/AppIcon.icns
#                      with iconutil (proves the compiled icns parses)
#   finder-<N>.png     the icon macOS itself shows for the bundle
#                      (NSWorkspace iconForFile, with the system's own icon
#                      treatment), at 512, 128, 32 and 16 points (2x pixels)
#
# Usage: app-icon-preview.sh path/to/LiveCaptions.app out-dir   (macOS only)
set -euo pipefail

app="${1:?usage: app-icon-preview.sh path/to/LiveCaptions.app out-dir}"
out="${2:?usage: app-icon-preview.sh path/to/LiveCaptions.app out-dir}"
icns="$app/Contents/Resources/AppIcon.icns"

fail() { echo "app-icon-preview: $*" >&2; exit 1; }

[[ -s "$icns" ]] || fail "missing $icns"
app="$(cd "$app" && pwd)"
rm -rf "$out"
mkdir -p "$out"
out="$(cd "$out" && pwd)"

iconutil -c iconset -o "$out/iconset" "$icns" || fail "iconutil cannot read $icns"
count="$(find "$out/iconset" -name '*.png' | wc -l | tr -d ' ')"
[[ "$count" -gt 0 ]] || fail "iconutil extracted no images from $icns"
echo "app-icon-preview: $count images from AppIcon.icns:"
ls -l "$out/iconset"

# JavaScript for Automation: AppKit without a Swift build step.
jxa="$(mktemp -d)/finder-icon.js"
trap 'rm -rf "$(dirname "$jxa")"' EXIT
cat >"$jxa" <<'EOF'
ObjC.import('AppKit');
function run(argv) {
  const app = argv[0], out = argv[1];
  const icon = $.NSWorkspace.sharedWorkspace.iconForFile(app);
  for (const points of [512, 128, 32, 16]) {
    const pixels = points * 2;
    const rep = $.NSBitmapImageRep.alloc.initWithBitmapDataPlanesPixelsWidePixelsHighBitsPerSampleSamplesPerPixelHasAlphaIsPlanarColorSpaceNameBytesPerRowBitsPerPixel(
      null, pixels, pixels, 8, 4, true, false, $.NSDeviceRGBColorSpace, 0, 0);
    rep.size = $.NSMakeSize(points, points);
    $.NSGraphicsContext.saveGraphicsState;
    $.NSGraphicsContext.currentContext = $.NSGraphicsContext.graphicsContextWithBitmapImageRep(rep);
    icon.drawInRectFromRectOperationFraction($.NSMakeRect(0, 0, points, points), $.NSZeroRect, $.NSCompositingOperationSourceOver, 1);
    $.NSGraphicsContext.restoreGraphicsState;
    const png = rep.representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $());
    const path = out + '/finder-' + points + '.png';
    if (!png.writeToFileAtomically(path, true)) throw new Error('cannot write ' + path);
    console.log('app-icon-preview: wrote ' + path);
  }
}
EOF
osascript -l JavaScript "$jxa" "$app" "$out" || fail "cannot render the Finder icon"
for points in 512 128 32 16; do
  [[ -s "$out/finder-$points.png" ]] || fail "missing $out/finder-$points.png"
done
