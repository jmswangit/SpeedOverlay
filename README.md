# SpeedOverlay

A standalone replacement for YTLite's broken **Speed controls** on iOS YouTube.

YTLite's speed display reads YouTube's internal `selectedVarispeedLabelText`, which no
longer returns anything on recent YouTube versions, so the current speed shows blank.
This tweak does not depend on that property — it tracks the playback rate itself and
draws its own controls.

## Features

- Adds `−` / current-speed / `+` buttons to the player overlay (left side).
- The current speed updates live as the rate changes (e.g. `1.25x`, `2x`).
- Tapping the current speed resets playback to `1x`.
- `−` / `+` step through `0.25x`–`5x`.
- Independent of YTLite/YTVideoOverlay; works on its own.

## Notes

- Turn off YTLite's own **Speed controls** (Settings → Player → Interface) to avoid
  duplicate controls.
- Disable/omit this tweak at build time (the `enable_speedoverlay` option in
  YTPlusYTweaks) if you don't want it.

## Build

```
make package FINALPACKAGE=1
```

Requires Theos plus [YouTubeHeader](https://github.com/PoomSmart/YouTubeHeader) on the
include path (`$THEOS/include/YouTubeHeader`). A GitHub Actions workflow is included
that sets this up and publishes the `.deb` and `.dylib`.
