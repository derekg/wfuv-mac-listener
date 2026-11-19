# Mac player design review

The goal is a small radio player that keeps the live controls in view while listeners browse songs. Scores are a qualitative review of the installed design before this pass and the rebuilt app after visual inspection, on a 1–5 scale.

| Area | Before | After | Change |
| --- | ---: | ---: | --- |
| Player identity | 2 | 4 | Album art and song details stay visible; a prominent play control anchors both sizes. |
| History navigation | 2 | 4 | Playlist and Favorites are first-class tabs; the player stays fixed while the song pane scrolls. |
| Action clarity | 2 | 4 | Every song row has a visible Spotify action and a separate favorite control. |
| Window sizing | 2 | 4 | A frameless mini card replaces the title-bar window, while the expanded layout gives more height to the playlist. |
| Motion and accessibility | 2 | 4 | Live audio bars and a subtle enlarged artwork glow add life; Reduce Motion suppresses the glow and bar animation. Controls retain accessibility labels. |

## Decisions

- Live radio has no seekable track progress, so the player uses a live indicator instead of a misleading progress bar.
- The red play/pause control is the primary action. Favorites and Spotify remain beside the song information in the expanded player.
- The history pane uses a separate scroll view so the player never scrolls away.
- The chevron collapses the entire window to a frameless 390 × 78 point card with artwork, song details, play/pause, expand, and close controls. Expanding restores the normal window chrome and the last selected Playlist or Favorites tab. The mode persists across launches.
- The expanded player puts play/pause beside the artwork to make room for more playlist rows. Each favorite still has a Spotify link that opens outside the app.
- The wide window is resizable from 390–720 points wide and 500–950 points tall. Album art and motion grow in the enlarged layout.

## Remaining limits

- At the minimum wide window height, only a few playlist rows fit at once; the list remains scrollable. Mini mode intentionally hides history.
- WFUV's playlist metadata can lag the live audio, and some recordings have no verified album art.
