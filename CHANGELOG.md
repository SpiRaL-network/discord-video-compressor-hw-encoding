# Changelog

## v2.1.0 — 2026-10-01

First release of the Hardware Encoding fork, based on Discord Shrinkwrap.

- Hardware-first automatic selection with real encoder probes, older H.264 GPU support
  and software fallback when hardware is unavailable or fails on a clip.
- Native Windows GUI with all configuration options, saved defaults, live logs,
  cancellation, drag-and-drop and a verified FFmpeg installer.
- Custom output names and `{name}` / `{index}` batch templates on both backends.
  Existing videos and duplicate basenames receive numbered names instead of blocking a run.
- Encoder dropdown explanations include vendor, codec and practical tradeoffs.
  Preset and rescue-quality choices include guidance; integer audio controls accept
  arbitrary supported targets such as 124 and 127 kbps.
- Exact decimal-MB caps, isolated cleanup, safe literal paths, corrected audio handling,
  bounded splitting and Windows/Linux regression coverage.
- Updated English and French documentation and audit notes. MIT license retained,
  including the original author's copyright and credits.
