# Code review and validation

This review covers the fork modifications and the inherited encoding/configuration,
download, cleanup and splitting paths. It is not a formal security certification.

## Corrections

- Hardware first on both backends, with real YUV420 probes and H.264 GPU candidates.
- Software retry if the chosen GPU fails on a real input; explicit software selection remains available.
- Exact decimal-byte cap instead of a rounded-up whole-megabyte threshold. Remuxed
  copies are checked again; failed/empty rescue encodes are not accepted.
- Per-invocation scratch directories replace broad filename-pattern cleanup in user output folders.
- Existing outputs and duplicate source basenames are rejected; inputs are read-only.
- Windows filesystem operations and logging handle literal paths with spaces, brackets, `!` and `&`.
- Corrupt/audio-only input is rejected before the copy path. Mono and normalization are
  honored on small clips; failed audio stripping falls through to encoding.
- Audio budget is not reserved for audio-free clips. Loudness cache keys use full paths;
  nonfinite measurements fall back to a single-pass filter on Windows.
- Split depth is bounded. Windows scratch names distinguish split inputs from encoding
  outputs, preventing the encoder from trying to overwrite its own input.
- Settings validate size, bitrates, retries and rescue quality. Missing ffprobe is fatal.
- GUI settings/path data travel as JSON/config data, not interpolated shell code.
  .NET event handlers stream logs; a Windows Job object supervises the worker and all
  child processes. A gate prevents the worker starting FFmpeg before job assignment.
- FFmpeg installer retains pinned version **8.1.1** and SHA-256
  `6f58ce889f59c311410f7d2b18895b33c03456463486f3b1ebc93d97a0f54541`.
  This matches the GitHub release asset digest. Its immutable GitHub fallback is
  available when the older gyan.dev web package is removed. Installer scratch names
  are unique; extraction is synchronous; ffprobe is required.
- Upstream copyright is retained and fork modifications are MIT. FFmpeg is external.

## Repeatable tests

`tests/windows.ps1` runs using Windows PowerShell 5.1 with generated video/audio.
It checks parser compatibility, x264/x265, automatic GPU/software selection, explicit
NVENC selection with fallback, exact byte limits, audio controls on small clips, MKV
remuxing, recursive splitting, corrupt input, protected outputs and source hashes,
preference round-trip/rejection, offscreen GUI construction and the actual GUI worker.
Cancellation checks that observed FFmpeg child processes exit with the worker.
An injected runtime GPU failure also verifies that the retry creates a real software-encoded H.264 file.

`tests/linux.sh` uses the same generated-clip approach for the Bash backend. It checks
software and auto encoding, exact caps, audio controls, remuxing, splitting, corrupt
input, invalid settings and output/log protection. GitHub Actions runs both suites.

Local testing also exercises actual NVIDIA **AV1 NVENC, HEVC NVENC and H.264 NVENC**.
No AMD AMF, Intel QSV, Apple VideoToolbox or macOS device is available for a real local
vendor test. Their functional probes and software fallback are retained, but full
driver/model coverage is not claimed. CPU/GPU speed and visual quality vary by clip;
the project does not claim a universal quality or speed winner.

## Remaining practical limits

- Decoder/filter/audio CPU use remains; hardware encoding does not imply an entirely GPU pipeline.
- AV1/HEVC playback varies by Discord client. H.264 is available explicitly.
- Cancel/forced termination retains hidden scratch folders; completed outputs remain intact.
- A mathematically difficult clip can need several split files or ultimately report failure.
- Output folders are intended for one batch at a time; use distinct folders for parallel jobs.
- No media is uploaded by the compressor. Only the explicit installer accesses the
  pinned FFmpeg download hosts. No credentials, telemetry or remote commands are added.
