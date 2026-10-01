#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
artifacts=${1:-"$root/test-artifacts-linux"}
mkdir -p "$artifacts"
artifacts=$(cd "$artifacts" && pwd)
cd "$artifacts"
trap 'for log in *.log; do echo "--- $log"; tail -n 30 "$log"; done' ERR
ffmpeg -hide_banner -loglevel error -f lavfi -i testsrc2=size=640x360:rate=30:duration=12 -f lavfi -i sine=frequency=400:duration=12 -c:v libx264 -preset ultrafast -crf 16 -g 30 -c:a aac -shortest -y 'clip [one] ! &.mp4'
run() { bash "$root/shrinkwrap.sh" "$@"; }
check_cap() {
    local dir=$1 cap=$2 count=0 file
    for file in "$dir"/*_optimized.mp4; do
        test -f "$file"
        test "$(stat -c%s "$file")" -le "$cap"
        test "$(stat -c%s "$file")" -gt 0
        ffprobe -v error -select_streams v:0 -show_entries stream=codec_type -of csv=p=0 "$file" | grep -qx video
        count=$((count+1))
    done
    test "$count" -gt 0
    test -z "$(find "$dir" -maxdepth 1 -name '.shrinkwrap-*' -print)"
}
run -c libx264 -p fast -t 1.4 -o x264 'clip [one] ! &.mp4' > x264.log
check_cap x264 1400000
run -c software -p fast -t 1.4 -o x265 'clip [one] ! &.mp4' > x265.log
check_cap x265 1400000
run -p fast -t 1.4 -o gpu-auto 'clip [one] ! &.mp4' > gpu-auto.log
check_cap gpu-auto 1400000
run -c libx264 -p fast -t 8 -l -m -o mono 'clip [one] ! &.mp4' > mono.log
test "$(ffprobe -v error -select_streams a:0 -show_entries stream=channels -of csv=p=0 'mono/clip [one] ! &_optimized.mp4')" = 1
run -c libx264 -t 8 -A -o silent 'clip [one] ! &.mp4' > silent.log
test -z "$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_type -of csv=p=0 'silent/clip [one] ! &_optimized.mp4')"
ffmpeg -hide_banner -loglevel error -i 'clip [one] ! &.mp4' -c copy -y remux.mkv
run -c libx264 -t 8 -o remux remux.mkv > remux.log
check_cap remux 8000000
run -c libx264 -p fast -t 0.45 -v 1000 -r 1 -o split 'clip [one] ! &.mp4' > split.log
check_cap split 450000
test "$(find split -name '*_PART_*_optimized.mp4' | wc -l)" -ge 2
printf 'keep me' > x264/my-important-pass.log
hash=$(sha256sum 'x264/clip [one] ! &_optimized.mp4')
if run -c libx264 -o x264 'clip [one] ! &.mp4' > collision.log 2>&1; then exit 1; fi
test "$(sha256sum 'x264/clip [one] ! &_optimized.mp4')" = "$hash"
test "$(cat x264/my-important-pass.log)" = 'keep me'
printf 'not a video' > corrupt.mp4
if run -o invalid corrupt.mp4 > invalid.log 2>&1; then exit 1; fi
if run -t NaN 'clip [one] ! &.mp4' > nan.log 2>&1; then exit 1; fi
echo 'PASS: Bash encoders, exact caps, audio, remux, split, corrupt input and output protection.'
