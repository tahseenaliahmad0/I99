#!/usr/bin/env bash
# Pictures of the subtitles (GDD 16.6) for artifacts/.
#
# Each one is the drive scene started with `--say=<line ids>` and saved with
# `--shot=` after so many frames at a fixed 60 a second:
#
#   short           a line of one line (noor.call.1)
#   two_lines       a line that needs two (narrator.start, 45 characters)
#   long_1, long_2  a line longer than two lines of 42 characters, in its
#                   two parts (subtitle.test.long, 143 characters)
#   exchange_1, _2  a row that holds an exchange, each under their own name
#                   (wreck.drivers.1)
#   queue_2         the second of three lines asked for at once
#   large, small    the Subtitles setting: size
#   no_background   the Subtitles setting: background off, by day
#   pointer         the pointer, aimed at the horn, is drawn over the subtitle
#   rtl             right-to-left: an Arabic subtitle under an Arabic name,
#                   from a line table made in memory (tools/subtitles_check.gd
#                   with --rtl-shot=; lines_ar.csv itself stays empty)
#   call            the line the simulation asks for: Dawn's road, the Call
#                   answered with a TAP on his pocket through the game's own
#                   input, the phone at his ear (--call-shot=)
#   key             the bay of the Arrival, the pointer on the key under the
#                   wheel, and a subtitle of two lines over it (--key-shot=)
#
#   tools/subtitles_shots.sh [output folder]     (default: artifacts)
#
# There is no GPU here: the pictures are drawn by Mesa under Xvfb
# (DECISIONS D-015). Set GODOT to use a specific engine binary.

set -eu
cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
OUT="$(mkdir -p "${1:-artifacts}" && cd "${1:-artifacts}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# shot <name> <frame> <leg> <line ids> [settings.json] [one more argument for the scene]
shot() {
  local name="$1" frame="$2" leg="$3" say="$4" settings="${5:-}"
  local user="$WORK/$name"
  mkdir -p "$user"
  if [ -n "$settings" ]; then
    printf '%s\n' "$settings" > "$user/settings.json"
  fi
  xvfb-run -a "$GODOT" --path . --rendering-method gl_compatibility --rendering-driver opengl3 \
    --audio-driver Dummy --fixed-fps 60 --quit-after $((frame + 120)) res://scenes/drive.tscn -- \
    "--leg=$leg" --bot=line "--say=$say" "--shot=$OUT/m10_subtitles_$name.png" "--shot-frame=$frame" \
    "--user-dir=$user" ${6:+"$6"} 2>&1 | grep -E '^\[drive\] shot|ERROR' || echo "no picture for $name"
}

shot short          60 night,2   noor.call.1
shot two_lines      60 night,2   narrator.start
shot long_1         60 night,2   subtitle.test.long
shot long_2        340 night,2   subtitle.test.long
shot exchange_1     60 night,2   wreck.drivers.1
shot exchange_2    140 night,2   wreck.drivers.1
shot queue_2       150 night,2   noor.call.1,heckle.uncles.doubt.1,heckle.aunts.order.tea
shot large          60 night,2   radio.news.patrol '{"subtitle_size": "large"}'
shot small          60 night,2   radio.news.patrol '{"subtitle_size": "small"}'
shot no_background  60 open_road radio.news.patrol '{"subtitle_background": false}'
shot pointer        70 night,2   radio.news.patrol '' --aim=horn

# tool_shot <name> <the argument of tools/subtitles_check.gd that takes it>
tool_shot() {
  xvfb-run -a "$GODOT" --path . --rendering-method gl_compatibility --rendering-driver opengl3 \
    --audio-driver Dummy --fixed-fps 60 --script res://tools/subtitles_check.gd -- \
    "--$2=$OUT/m10_subtitles_$1.png" 2>&1 | grep -E '^shot|ERROR' || echo "no picture for $1"
}

tool_shot rtl  rtl-shot
tool_shot call call-shot
tool_shot key  key-shot
