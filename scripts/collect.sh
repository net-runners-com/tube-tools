#!/usr/bin/env bash
# Downloads yt-dlp, Deno and ffmpeg for every platform Tube runs on, verifies each against the
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

# ---- Deno: yt-dlp's JavaScript runtime for YouTube's player
DENO=$(latest_tag denoland/deno)
while read -r key target; do
  zip="deno-$target.zip"
  fetch "https://github.com/denoland/deno/releases/download/$DENO/$zip" "$zip"
  fetch "https://github.com/denoland/deno/releases/download/$DENO/$zip.sha256sum" "$zip.sha"
  # sha256sum format on most targets, PowerShell's Get-FileHash table on Windows: take the 64-hex value
  check "$zip" "$(grep -oiE '[0-9a-f]{64}' "$zip.sha" | head -1 | tr 'A-F' 'a-f')"
  out="deno-$key.zip"
  cp "$zip" "$OUT/$out"
  add deno "$DENO" "$key" "$out"
done <<'EOF'
darwin-arm64 aarch64-apple-darwin
darwin-x64 x86_64-apple-darwin
win32-x64 x86_64-pc-windows-msvc
win32-arm64 x86_64-pc-windows-msvc
linux-x64 x86_64-unknown-linux-gnu
linux-arm64 aarch64-unknown-linux-gnu
EOF

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
  url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://ffmpeg.martin-riedl.de/redirect/latest/macos/$plat/release/ffmpeg.zip")
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
