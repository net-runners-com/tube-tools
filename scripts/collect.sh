#!/usr/bin/env bash
# Downloads yt-dlp, Node.js and ffmpeg for every platform Tube runs on, verifies each against the
# checksum its publisher posts, repackages them as zips and writes manifest.json:
#   { "tools": { "<tool>": { "version": "...", "assets": { "<os>-<arch>": { "file": "...", "sha256": "..." } } } } }
# <os> is Node's process.platform (darwin, win32, linux); <arch> is process.arch (x64, arm64).
set -euo pipefail
OUT=${1:-out}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

fetch() { curl -fsSL --retry 3 -o "$2" "$1"; }
check() { # file expected-sha256
  local got
  got=$(sha256sum "$1" | cut -d' ' -f1)
  [ "$got" = "$2" ] || { echo "checksum mismatch for $1: $got != $2" >&2; exit 1; }
}
sumof() { grep -E "[ *]$2\$" "$1" | head -1 | cut -d' ' -f1; }
latest_tag() { curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" | sed 's#.*/##'; }

MANIFEST='{"tools":{}}'
add() { # tool version key file
  local sha
  sha=$(sha256sum "$OUT/$4" | cut -d' ' -f1)
  MANIFEST=$(jq --arg t "$1" --arg v "$2" --arg k "$3" --arg f "$4" --arg s "$sha" \
    '.tools[$t].version = $v | .tools[$t].assets[$k] = {file: $f, sha256: $s}' <<<"$MANIFEST")
}

# ---- yt-dlp: the official "onedir" builds (fast start), as published
YT=$(latest_tag yt-dlp/yt-dlp)
fetch "https://github.com/yt-dlp/yt-dlp/releases/download/$YT/SHA2-256SUMS" yt.sums
while read -r key asset; do
  fetch "https://github.com/yt-dlp/yt-dlp/releases/download/$YT/$asset" "$asset"
  check "$asset" "$(sumof yt.sums "$asset")"
  out="yt-dlp-$key.zip"
  cp "$asset" "$OUT/$out"
  add yt-dlp "$YT" "$key" "$out"
done <<'EOF'
darwin-arm64 yt-dlp_macos.zip
darwin-x64 yt-dlp_macos.zip
win32-x64 yt-dlp_win.zip
win32-arm64 yt-dlp_win_arm64.zip
linux-x64 yt-dlp_linux.zip
linux-arm64 yt-dlp_linux_aarch64.zip
EOF

# ---- Node.js (current LTS): yt-dlp's JavaScript runtime for YouTube's player. Only the node
# program is kept (no npm), checked against nodejs.org's SHASUMS256.txt.
NODE=$(curl -fsSL https://nodejs.org/dist/index.json | jq -r '[.[] | select(.lts != false)][0].version')
fetch "https://nodejs.org/dist/$NODE/SHASUMS256.txt" node.sums
while read -r key asset; do
  fetch "https://nodejs.org/dist/$NODE/$asset" "$asset"
  check "$asset" "$(sumof node.sums "$asset")"
  rm -rf x && mkdir x
  case "$asset" in
    *.zip) unzip -q "$asset" -d x ;;
    *.tar.xz) tar -xJf "$asset" -C x ;;
    *.tar.gz) tar -xzf "$asset" -C x ;;
  esac
  bin=$(find x -type f \( -path '*/bin/node' -o -name node.exe \) | head -1)
  out="node-$key.zip"
  (cd "$(dirname "$bin")" && zip -q -9 "$OUT/$out" "$(basename "$bin")")
  add node "$NODE" "$key" "$out"
done <<EOF2
darwin-arm64 node-$NODE-darwin-arm64.tar.gz
darwin-x64 node-$NODE-darwin-x64.tar.gz
win32-x64 node-$NODE-win-x64.zip
win32-arm64 node-$NODE-win-arm64.zip
linux-x64 node-$NODE-linux-x64.tar.xz
linux-arm64 node-$NODE-linux-arm64.tar.xz
EOF2

# ---- ffmpeg: one program per platform, repackaged as a zip holding just ffmpeg(.exe)
FFB=https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest
fetch "$FFB/checksums.sha256" ff.sums
FFVER=""
while read -r key asset; do
  fetch "$FFB/$asset" "$asset"
  check "$asset" "$(sumof ff.sums "$asset")"
  rm -rf x && mkdir x
  case "$asset" in
    *.zip) unzip -q "$asset" -d x ;;
    *.tar.xz) tar -xJf "$asset" -C x ;;
  esac
  bin=$(find x -type f \( -name ffmpeg -o -name ffmpeg.exe \) | head -1)
  [ -z "$FFVER" ] && [ "${bin##*.}" != exe ] && FFVER=$("$bin" -version | head -1 | awk '{print $3}')
  out="ffmpeg-$key.zip"
  (cd "$(dirname "$bin")" && zip -q -9 "$OUT/$out" "$(basename "$bin")")
  add ffmpeg "${FFVER:-latest}" "$key" "$out"
done <<'EOF'
win32-x64 ffmpeg-master-latest-win64-gpl.zip
win32-arm64 ffmpeg-master-latest-winarm64-gpl.zip
linux-x64 ffmpeg-master-latest-linux64-gpl.tar.xz
linux-arm64 ffmpeg-master-latest-linuxarm64-gpl.tar.xz
EOF
# macOS: static builds by Martin Riedl (FFmpeg-Builds has none), each with its .sha256
while read -r key plat; do
  # this redirect answers HEAD with 404: follow it with a 1-byte GET instead
  url=$(curl -fsSL -r 0-0 -o /dev/null -w '%{url_effective}' "https://ffmpeg.martin-riedl.de/redirect/latest/macos/$plat/release/ffmpeg.zip")
  fetch "$url" "mac-$plat.zip"
  check "mac-$plat.zip" "$(curl -fsSL "$url.sha256" | cut -d' ' -f1)"
  out="ffmpeg-$key.zip"
  rm -rf x && mkdir x && unzip -q "mac-$plat.zip" -d x
  bin=$(find x -type f -name ffmpeg | head -1)
  chmod 755 "$bin"
  (cd "$(dirname "$bin")" && zip -q -9 "$OUT/$out" ffmpeg)
  add ffmpeg "${FFVER:-latest}" "$key" "$out"
done <<'EOF'
darwin-arm64 arm64
darwin-x64 amd64
EOF

jq --arg at "$(date -u +%FT%TZ)" '.built = $at' <<<"$MANIFEST" > "$OUT/manifest.json"
cat "$OUT/manifest.json"
