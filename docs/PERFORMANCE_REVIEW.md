# Performance review

Snapshot from a running Mac mini on November 21, 2026. These numbers describe one app instance after about 18 hours of uptime; they are not peak measurements or a substitute for a long Instruments trace.

| Measure | Observed | Limit or behavior |
| --- | ---: | --- |
| Process resident memory (`ps` RSS) | 38,976 KiB (38.1 MiB) | A single snapshot cannot establish a memory trend. |
| CPU (`top`, three samples over ~5 seconds) | 0.0%, 0.3%, 0.4% | Low activity while the app was running. |
| Managed artwork directory | 29 MB, 400 image files | Pruned to at most 400 images and 80 MB. |
| System URL cache directory | 12 MB | Separate from the managed artwork directory; this is the observed size, not a configured cap. |
| Artwork index | 98 KB, 520 records | 114 records represent missing art; the rest mainly point to cached covers. |

After installing this change and expanding and collapsing the player, a second process snapshot showed 46,128 KiB (45.0 MiB) RSS at 51 seconds of uptime. Three more CPU samples read 0.0%. The two memory snapshots had different uptimes and cache states, so they do not establish an improvement or regression; they show no large footprint in either state.

## Workload and bounds

- While the player window is visible, the app requests WFUV's playlist and now-playing metadata once every 45 seconds. Closing the window stops this polling; audio playback can continue through `AVPlayer`.
- Artwork is requested for the current song and the first four recent songs. Further rows load art when they appear. The artwork service coalesces requests for the same recording, stores normalized images of at most 600 pixels, and backs off after missing art or server failures.
- The artwork service's in-memory `NSCache` is capped at 40 compressed images or 20 MB. The view model is now capped at 24 compressed images or 12 MB and publishes a single dictionary update when it inserts or evicts an image.
- Restoring a cached image no longer republishes identical bytes when the artwork service returns the same image. This avoids an unnecessary SwiftUI update on first load.
- The large artwork glow and live bars run only in the expanded player while audio is live. Reduce Motion suppresses those animations. The mini player has no continuous animation.

## Remaining trade-off

On a cache miss, a difficult album-art lookup can still try several MusicBrainz release groups and Cover Art Archive URLs. This favors cover coverage but costs network requests and time for uncommon tracks. The search is throttled, concurrent cover checks are limited to groups of three, and missing results are cached for a day. Any lower candidate limit should be tested against artwork coverage before changing it.
