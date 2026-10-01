# Discord Video Compressor — Hardware Encoding

A small, local video compressor for Discord, with **GPU encoding by default** and a
**native Windows GUI**. Based on [Discord Shrinkwrap by nunogomes255](https://github.com/nunogomes255/discord-video-compressor).
Thank you, Nuno, for the original constraint-based pipeline, encoder probes and cross-platform scripts.
This fork and its changes remain **MIT licensed**, with the original copyright retained.

[Guide en français](README.fr.md) · [Changelog](CHANGELOG.md) · [Audit and testing](AUDIT.md)

## What changed from upstream

- `auto` now means hardware first, on both Windows and Bash. The default priority is
  **AV1 → HEVC → H.264**, then software `libx265` / `libx264`. Older H.264-only GPUs are included.
- Hardware candidates are tested with a short, real YUV420 encoding using the selected
  rate-control/preset settings. A compiled-in encoder is not enough. VideoToolbox is
  required to use hardware; software emulation is disabled. If a real clip fails GPU
  encoding after the probe, it is retried in software.
- `open_compressor.bat` opens a Windows GUI: video/folder selection, drag-and-drop,
  encoder and preset selection, size cap, audio controls, advanced settings, saved
  defaults, live stage/batch logs, cancellation, output-folder access and verified FFmpeg setup.
- **Output name** lets you name the result without renaming the source. Encoder menus
  explain the hardware vendor, codec and tradeoffs; preset and rescue-quality menus
  include guidance. Audio bitrates accept any integer in the supported range.
- File sizes use **decimal MB (1 MB = 1,000,000 bytes)** and the exact requested cap.
  The upstream rounded-up acceptance threshold is removed. A `19.8` target means at
  most `19,800,000` bytes, including the container and audio.
- Audio controls also apply to clips already below the cap. Failed audio removal never
  silently copies the original audio back. Under-cap non-MP4 inputs are remuxed and rechecked.
- Temporary files are isolated per run. Cleanup only deletes that run's scratch folder.
  Existing outputs stay intact; new results and duplicate input basenames are numbered automatically.
- Corrupt/audio-only input is rejected, odd video widths are made encoder-safe, splitting
  is bounded, and failed batches return a nonzero exit code. Automated Windows/Linux
  regression tests accompany these changes.

## Windows quick start

1. Download the portable ZIP from [Releases](https://github.com/SpiRaL-network/discord-video-compressor-hw-encoding/releases/latest),
   or use **Code → Download ZIP**, then extract the whole folder.
2. Double-click **`open_compressor.bat`**.
3. If FFmpeg is missing, click **Install FFmpeg**. The download is pinned to a release
   and verified with SHA-256 before extraction. You can instead put `ffmpeg.exe` and
   `ffprobe.exe` beside the scripts, or provide both on `PATH`.
4. Add videos or folders, or drag them into the list. Keep `Encoder = auto` for GPU selection.
5. Set your upload cap and optionally **Output name**, then click **Compress videos**. Results and summary reports go
   to `optimized` by default. Click **Open output** to find them.

![Windows GUI with encoder guidance and a custom output name field](docs/gui.png)

Requires Windows 10/11 and **Windows PowerShell 5.1 / .NET Framework** (included with
Windows). No Python, Node, web server, account or upload is involved. The GUI is Windows
only; Linux and macOS retain the Bash CLI. Hover over controls for help. Progress shows
the current stage and batch file; it does not invent a per-frame percentage on Windows.

**Simple drag-and-drop is still available:** drag videos or a folder onto
`drag_videos_here.bat`, or double-click it to compress videos beside the scripts.
Windows may require you to unblock downloaded scripts in File Properties.

## Picking an encoder

| Selection | Behavior |
|---|---|
| `auto` or `hw` | First working hardware encoder in the configured priority list; otherwise software. |
| `software` | Prefer `libx265`, then `libx264`, using two passes. |
| `software_x264` / `libx264` | H.264 software for broad playback support. |
| Specific name | Probe that encoder; fall back to software if unavailable. |

Default GPU order:

```text
av1_amf av1_nvenc av1_qsv
hevc_amf hevc_nvenc hevc_qsv hevc_videotoolbox
h264_nvenc h264_amf h264_qsv h264_videotoolbox
```

“Best” means the first usable encoder in this codec/vendor preference list; this is not
a benchmark of all GPUs. Reorder it in the GUI's **Advanced** tab or in `shrinkwrap.conf`.
For broad inline playback, select `h264_nvenc`, `h264_amf`, `h264_qsv`,
`h264_videotoolbox` or `libx264`. AV1 and HEVC can be more efficient, but playback varies
across Discord clients/devices. Hardware prioritizes speed; software two-pass encoding
can deliver better quality at very small bitrates. Decode, scaling and audio processing
can still consume CPU even when video encoding runs on the GPU.

Preset names are mapped to the active encoder: `fast` / `medium` / `slow` select a
speed/quality tier; native NVENC `p1`…`p7`, AMF `speed` / `balanced` / `quality` and
x264/QSV presets are accepted. NVENC uses capped VBR with internal multipass;
AMF/QSV/VideoToolbox use their supported rate-control settings. Every final file is
size-checked: rate-control flags alone are not a size guarantee.

## Naming outputs and choosing quality

Leave **Output name** blank for `clip_optimized.mp4`, or enter `My Discord clip`
(the `.mp4` extension is optional). Existing videos are preserved: another run creates
`My Discord clip (2).mp4`, then `(3)`, and so on. Duplicate source names in a batch
also get distinct outputs. Inputs are never renamed or modified.

For batches, use `{name}` for the source basename and `{index}` for `001`, `002`, etc.
For example, `Discord {name} {index}` produces `Discord clip 001.mp4`. A constant
name such as `Highlights` becomes `Highlights_001.mp4`, `Highlights_002.mp4`.
Split clips add `_PART_…` to the chosen name. The output name is a filename;
choose its directory separately with **Output folder**.

The encoder dropdown shows vendor/CPU, codec, compression efficiency and playback
tradeoffs in parentheses. **Speed / quality** describes the preset's speed/quality
tradeoff. **Rescue quality (CRF / CQ)** offers suggested values and accepts custom
integers from 1 to 51: lower values preserve more detail but can need more space.
It controls the fallback encoding stage, not the resolution. Resolution adjustment
remains automatic when needed to fit the cap.

AAC audio bitrates are targets, not a fixed list of modes: `124` and `127` kbps are
valid. The GUI provides integer controls from 16 to 512 kbps for initial and minimum
audio bitrate; the initial value must be at least the minimum. Video bitrate is
calculated automatically; its minimum is also an integer control.

## Command line

```powershell
# Windows: GPU first, 19.8 decimal MB maximum
.\shrinkwrap.ps1 -Files "clip.mp4"
.\shrinkwrap.ps1 -Encoder h264_nvenc -TargetSizeMB 19.8 -Files "clip.mp4"
.\shrinkwrap.ps1 -Encoder software -Preset fast -Files "clip.mp4"
.\shrinkwrap.ps1 -NormalizeAudio -Mono -Files "clip.mp4"
.\shrinkwrap.ps1 -NoAudio -Files "clip.mp4"
.\shrinkwrap.ps1 -TargetSizeMB 49 -OutputDir "output-new" -Files "clip.mp4"
.\shrinkwrap.ps1 -OutputName "My Discord clip.mp4" -Files "clip.mp4"
```

```bash
# Linux / macOS: FFmpeg, ffprobe, bc, awk and Bash 4+ are required
bash shrinkwrap.sh clip.mp4
bash shrinkwrap.sh -c h264_nvenc -t 19.8 clip.mp4
bash shrinkwrap.sh -c software -p fast clip.mp4
bash shrinkwrap.sh -l -m clip.mp4
bash shrinkwrap.sh -A clip.mp4
bash shrinkwrap.sh -t 49 -o output-new clip.mp4
bash shrinkwrap.sh -N 'Discord {name} {index}' clip.mp4
```

Linux: install `ffmpeg bc gawk` through your distribution's package manager.
macOS: `brew install ffmpeg bash`; run using the Homebrew Bash, since Apple's built-in
Bash 3.2 does not support the associative arrays used by this pipeline.
With no files supplied, either CLI scans the current directory. Windows also accepts
folders recursively. Already generated `_optimized.mp4` files are skipped.

| Setting | Windows parameter | Bash option | Default |
|---|---|---|---|
| Encoder | `-Encoder` | `-c` | `auto` (hardware first) |
| Size cap, decimal MB | `-TargetSizeMB` | `-t` | `19.8` |
| Preset | `-Preset` | `-p` | `slow` |
| Minimum video kbps | `-MinVideoBitrate` | `-v` | `500` |
| Minimum audio kbps | `-MinAudioBitrate` | `-a` | `64` |
| Initial audio kbps | `-AudioBitrate` | config `audio_bitrate` | `192` |
| Rescue CRF/CQ | `-CrfRescueValue` | config `crf_rescue_value` | `28` |
| Attempts per resolution | `-MaxRetries` | `-r` | `3` |
| Loudness normalization | `-NormalizeAudio` | `-l` | off |
| Mono | `-Mono` | `-m` | off |
| Remove audio | `-NoAudio` | `-A` | off |
| Output folder | `-OutputDir` | `-o` | `optimized` |
| Output name / template | `-OutputName` | `-N` | source name + `_optimized` |
| Keep scratch/logs | `-NoCleanup` | `-n` | off |
| Save encoder preference wizard | `-Config` | `--config` | explicit only |
| Disable terminal pause | `-NonInteractive` | automatic | off |
| Explicit config snapshot | `-ConfigPath` | — | standard search |

The video bitrate is calculated from duration, size, container overhead and audio
budget; the minimum bitrate is a floor, not a fixed bitrate override. The pipeline
retries toward the requested size, reclaims headroom once when appropriate, then uses
rescue encodes/downscaling and keyframe splitting for difficult clips. The source file
is never modified. A small clip may be copied/remuxed losslessly when audio processing
is not requested.

## Saved defaults

The GUI's **Save defaults** writes `shrinkwrap.conf`. Both CLIs read it, so the GUI and
drag-and-drop launcher share preferences. CLI arguments override saved settings.
The script folder takes precedence over `%APPDATA%/discord-video-compressor` on
Windows or `$XDG_CONFIG_HOME/discord-video-compressor` (`~/.config` by default) on Unix.
If the script folder cannot be written, saving falls back to the user folder.
Deleting the file restores this fork's hardware-first defaults. An existing upstream
`mode = software` preference remains honored until you change it.

All existing configuration keys are exposed in the GUI. Example:

```ini
mode = hardware
hardware_order = av1_amf av1_nvenc av1_qsv hevc_amf hevc_nvenc hevc_qsv hevc_videotoolbox h264_nvenc h264_amf h264_qsv h264_videotoolbox
software_order = libx265 libx264
target_size_mb = 19.8
preset = slow
normalize_audio = false
mono = false
no_audio = false
audio_bitrate = 192
min_audio_bitrate = 64
min_video_bitrate = 500
max_retries = 3
crf_rescue_value = 28
output_dir = optimized
output_name =
no_cleanup = false
```

`mode` also accepts `software`, `software_x264` or a supported explicit encoder name.
The GUI uses a private per-run snapshot, so changing saved defaults cannot change a
compression that is already running. No preference text is executed as code.

## Troubleshooting and limits

- **Existing output / duplicate basename:** new outputs are numbered automatically.
  Use **Output name** to customize them; previous videos remain intact.
- **GPU unavailable:** check the selected encoder in the log; a GPU driver and a
  compatible FFmpeg build are required. Software fallback is automatic.
- **Failed clip:** the batch reports failures and returns exit code `1`. Other completed
  files are retained. Enable **Keep temporary files and logs** before reproducing the
  failure; the hidden `.shrinkwrap-*` folder contains FFmpeg diagnostics.
- **Cancel:** the GUI stops the worker and its FFmpeg descendants. Completed files stay;
  abruptly interrupted scratch folders stay hidden in the output folder and can be
  removed manually. Normal completion cleans only that run's scratch folder.
- **Very long clip / very small cap:** splitting can produce several files. Recursion is
  bounded and a failed rescue is reported rather than running indefinitely.
- **Upload cap:** `19.8 MB` is a conservative default. Set the value for the limit shown
  in your Discord account/server; those limits can vary. See Discord's
  [attachment FAQ](https://support.discord.com/hc/en-us/articles/25444343291031-File-Attachments-FAQ).

## Development and credits

```powershell
.\setup-ffmpeg.ps1 -NonInteractive
.\tests\windows.ps1
```

```bash
bash -n shrinkwrap.sh
bash tests/linux.sh
```

Tests use generated clips and verify actual output bytes, codecs/audio, custom names,
collision numbering, batch templates, splitting,
invalid input, output protection, preferences, the Windows GUI worker and cancellation.
GitHub Actions runs the Windows PowerShell 5.1 and Ubuntu suites on pushes and pull requests.
GPU tests use software fallback on machines without suitable hardware; they are not a
claim that every GPU vendor/model has been tested. See [AUDIT.md](AUDIT.md).

Original project: **[nunogomes255/discord-video-compressor](https://github.com/nunogomes255/discord-video-compressor)**.
Fork: **[SpiRaL-network/discord-video-compressor-hw-encoding](https://github.com/SpiRaL-network/discord-video-compressor-hw-encoding)**.
Scripts and GUI: [MIT](LICENSE). FFmpeg is a separately licensed dependency; its binaries
are not committed to this repository. Encoder behavior follows the
[FFmpeg codec documentation](https://ffmpeg.org/ffmpeg-codecs.html).
