# Butlerly confirmation sounds

The **More → Sound for saving/updating** preference controls optional offline
feedback for a successfully saved transaction. No sound is played for a failed
save, a canceled edit, or while the preference is disabled.

| Event | Bundled asset | Duration |
| --- | --- | --- |
| New transaction saved | `assets/audio/item_created.wav` | 1.30 s |
| Existing transaction updated | `assets/audio/item_updated.wav` | 1.10 s |
| More setting switches Off → On after persistence succeeds | creation sound | 1.30 s |

Both repository-bundled WAVs are **original, independently synthesized** tones
(44.1 kHz, 16-bit, mono). They are reproducible with
`python3 tool/generate_confirmation_sounds.py`; no third-party sound-pack
recordings or samples are included in the public repository.

## Private use of the two selected QuietCog samples

The original QuietCog success chime and soft message ding that were selected
during design are kept **outside this public repository**. QuietCog's free
sample license permits including and editing these sounds *inside applications*
but prohibits re-uploading or giving away the standalone WAV files (original
or modified). Publicly committing or distributing the raw files is therefore
not covered by the license.

To use the exact two selected QuietCog sounds in a **private local build**,
replace the two corresponding WAV assets in your checkout with the files from
your separately obtained private integration kit (same filenames). **Do not
commit, push, or upload the replacements into the public Git repository**.
A clean checkout will continue to use the original Butlerly-generated tones.
The same source paths and playback behavior work for both sound choices.

Do not overwrite the publicly tracked WAV files in a branch you intend to
publish without restoring the original generated assets first:

```sh
python3 tool/generate_confirmation_sounds.py
git status --short apps/butlerly/assets/audio/
```

The More preference is persisted by `userPreferenceProvider`. Playback is
best effort and must not turn a successful database commit into a failure.
