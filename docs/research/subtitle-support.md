# Subtitle support research

## User outcome

Cinema Player should make locally stored films usable for multilingual viewing without requiring a codec pack or a network service. This change focuses on readable subtitle controls, timing correction, and predictable support for both common subtitle sources.

## Platform findings

- AVFoundation models embedded subtitle and closed-caption tracks as a media-selection group with the `legible` characteristic. A custom player UI can list an `AVMediaSelectionGroup` and select an `AVMediaSelectionOption` on the `AVPlayerItem`.
- Apple documents that selecting one of those legible options displays it in `AVPlayerView`, which lets Cinema Player keep native rendering for embedded tracks.
- `AVPlayerItemLegibleOutput` exposes attributed text from a player item, but it is not a parser or attachment mechanism for a standalone `.srt` file. An external SRT therefore needs its own parser and overlay.

Sources: [Selecting subtitles and alternative audio tracks](https://developer.apple.com/documentation/avfoundation/selecting-subtitles-and-alternative-audio-tracks?changes=__2), [AVMediaCharacteristic.legible](https://developer.apple.com/documentation/avfoundation/avmediacharacteristic/legible), and [AVPlayerItemLegibleOutput](https://developer.apple.com/documentation/avfoundation/avplayeritemlegibleoutput).

## Product decision

The implementation deliberately uses two rendering paths:

1. **Embedded tracks** are selected through AVFoundation and rendered by the native player.
2. **External `.srt` files** are parsed locally and rendered in a Cinema Player overlay, with a ±10-second timing offset for imperfect releases.

The overlay is independent from the auto-hiding control deck, so subtitles remain visible during distraction-free playback. The parser accepts standard comma or dot millisecond separators, multi-line cues, byte-order marks, and gracefully skips malformed blocks while retaining valid cues.
