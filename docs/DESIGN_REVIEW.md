# Mac player design review

The goal is a small radio player that keeps the live controls in view while listeners browse songs. Scores are a qualitative review of the installed design before this pass and the rebuilt app after visual inspection, on a 1–5 scale.

| Area | Before | After | Change |
| --- | ---: | ---: | --- |
| Player identity | 2 | 4 | Larger album art, more legible song type, and a central play control give the broadcast its own space. |
| History navigation | 2 | 4 | The player and station header stay fixed; only the song pane scrolls. |
| Action clarity | 2 | 4 | Every song row has a visible Spotify action and a separate favorite control. |
| Window sizing | 2 | 4 | A useful compact size and a capped enlarged size keep the history pane scrollable. |
| Motion and accessibility | 2 | 4 | Live audio bars and a subtle enlarged artwork glow add life; Reduce Motion suppresses the glow and bar animation. Controls retain accessibility labels. |

## Decisions

- Live radio has no seekable track progress, so the player uses a live indicator instead of a misleading progress bar.
- The large red play/pause control is the primary action. Favorites and Spotify remain beside the song information.
- The history pane uses a separate scroll view so the player never scrolls away.
- The chevron collapses the player to a fixed strip with artwork, song details, and play/pause. The choice persists across launches and can be reversed without losing the history view.
- The window is bounded to 390–720 points wide and 500–950 points tall. Album art and motion grow in the enlarged layout.

## Remaining limits

- A very short window shows only one history row with the full player; the collapsed strip exposes several rows without moving the playback control.
- WFUV's playlist metadata can lag the live audio, and some recordings have no verified album art.
