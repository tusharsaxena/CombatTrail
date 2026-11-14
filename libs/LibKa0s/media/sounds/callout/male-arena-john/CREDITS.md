# Callout voice pack: male-arena-john

Forty-three spoken call-outs for `LibKa0s-Callout-1.0`: the numbers `1.ogg` to `20.ogg` and the stock
lines (`ready`, `go`, `start`, `stop`, `warning`, `error`, `done`, `finish`, `new_best`, `pause`,
`resume`, `canceled`, `pull`, `interrupt`, `move`, `defensive`, `rebuff`, `expiring`, `upgrade`,
`time_up`, `victory`, `failed`, `last_ten`). Each clip was synthesized with Piper and then processed into an arena-announcer sound; no person recorded
these lines.

## Voice

- Voice: Piper `en_US-john-medium` (US English, male, one speaker, 22,050 Hz).
- Model: <https://huggingface.co/rhasspy/piper-voices/tree/main/en/en_US/john/medium>, model card
  <https://huggingface.co/rhasspy/piper-voices/blob/main/en/en_US/john/medium/MODEL_CARD>.
  The piper-voices repository is published under the MIT license.
  `en_US-john-medium.onnx` SHA-256
  `789c6c875726e627ddee93d51d8727859abe9c091c3d141591f4b83c2072e988`.
- Dataset: about 12.5 hours of LibriVox recordings (<https://librivox.org>) assembled by Bryce Beattie,
  <https://brycebeattie.com/files/tts/>. License: public domain (LibriVox recordings are public domain
  in the US, <https://librivox.org/pages/public-domain/>); the model author states the voice's license
  as public domain. Status recorded in `LICENSE-PUBLIC-DOMAIN.txt`.
- Base model: the voice was fine-tuned for 600 epochs from Bryce Beattie's `en_US-kristin-medium`,
  itself trained from scratch on LibriVox recordings, <https://huggingface.co/rhasspy/piper-voices/blob/main/en/en_US/kristin/medium/MODEL_CARD>.
  License: public domain.

## Generation

- Generator: piper-tts 1.8.0 (Python), <https://github.com/OHF-Voice/piper1-gpl>, with `noise_scale` 0.5
  and `noise_w` 0.333, `length_scale` 0.9 (a little faster than the 1.0 default).
- Takes: this voice tends to run on after a short word, so each line was synthesized 15 times
  (the text as above, bare, with a trailing comma, with a trailing period, and lower-case, each at
  `noise_scale` 0.33, 0.5 and 0.667) and the shortest take with a single run of speech per word was
  kept.
- Text: each line as a word or phrase ending in `!` (numbers as words, `last_ten` as "Ten
  seconds!"), except `pause`, `canceled` and `failed`, which end in a period.
- Source: the same 43 takes as the `male-john` pack, before its trim and normalize.
- Processing (own work, in ffmpeg 9.0.2 (the imageio-ffmpeg build) and numpy): trimmed and peak-normalized to -3 dBFS;
  pitch -3 semitones at unchanged tempo (rubberband, crisp transients); high-pass 55 Hz, low shelf
  +4 dB at 140 Hz, -3 dB at 350 Hz, +4 dB at 2.6 kHz; compressor 8:1 (3 ms attack, 90 ms release,
  +6 dB makeup); tanh soft clip, +4 dB drive into an atan soft clip, limiter; a synthetic 1.8 s hall
  reverb (seeded noise impulse response, darkening tail, four early reflections) mixed at -9 dB;
  tanh bus saturation. Each clip keeps its reverb tail, capped at 0.8 s past the dry speech with a
  0.35 s fade (in game the countdown clips play 1 s apart). Then trimmed at 42 dB below peak with
  10 ms kept and an 80 ms fade, and peak-normalized to -1 dBFS (gain lowered further on clips whose
  Vorbis decode would otherwise peak above -0.5 dBFS).
- The public-domain source permits this derivative; the processing adds no license terms.
- Encoding: Ogg Vorbis, mono, 22,050 Hz, about quality 4 (libsndfile 1.2.2 through python-soundfile,
  compression level 0.6).
- Generated 2026-11-14.
