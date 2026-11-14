# Callout voice pack: male-norman

Forty-three spoken call-outs for `LibKa0s-Callout-1.0`: the numbers `1.ogg` to `20.ogg` and the stock
lines (`ready`, `go`, `start`, `stop`, `warning`, `error`, `done`, `finish`, `new_best`, `pause`,
`resume`, `canceled`, `pull`, `interrupt`, `move`, `defensive`, `rebuff`, `expiring`, `upgrade`,
`time_up`, `victory`, `failed`, `last_ten`). Each clip was synthesized with Piper; no person recorded
these lines.

## Voice

- Voice: Piper `en_US-norman-medium` (US English, male, one speaker, 22,050 Hz).
- Model: <https://huggingface.co/rhasspy/piper-voices/tree/main/en/en_US/norman/medium>, model card
  <https://huggingface.co/rhasspy/piper-voices/blob/main/en/en_US/norman/medium/MODEL_CARD>.
  The piper-voices repository is published under the MIT license.
  `en_US-norman-medium.onnx` SHA-256
  `b9739443232a80a59c7d18810dd856899bf16a7964725f5ab81ea49b1351cb71`.
- Dataset: about 15.5 hours of LibriVox recordings (<https://librivox.org>) assembled by Bryce Beattie,
  <https://brycebeattie.com/files/tts/>. License: public domain (LibriVox recordings are public domain
  in the US, <https://librivox.org/pages/public-domain/>); the model author states the voice's license
  as public domain. Status recorded in `LICENSE-PUBLIC-DOMAIN.txt`.
- Base model: none; the voice was trained from scratch (1200 epochs, medium quality settings).

## Generation

- Generator: piper-tts 1.8.0 (Python), <https://github.com/OHF-Voice/piper1-gpl>, with `noise_scale` 0.5
  and `noise_w` 0.333, `length_scale` 0.9 (a little faster than the 1.0 default).
- Takes: this voice tends to run on after a short word, so each line was synthesized 15 times
  (the text as above, bare, with a trailing comma, with a trailing period, and lower-case, each at
  `noise_scale` 0.33, 0.5 and 0.667) and the shortest take with a single run of speech per word was
  kept.
- Text: each line as a word or phrase ending in `!` (numbers as words, `last_ten` as "Ten
  seconds!"), except `pause`, `canceled` and `failed`, which end in a period.
- Post-processing: leading and trailing silence trimmed at 45 dB below the clip's peak with 15 ms
  kept on each side and a 5 ms fade, then peak-normalized to -1 dBFS (gain lowered further on the
  few clips whose Vorbis decode would otherwise peak above -0.5 dBFS).
- Encoding: Ogg Vorbis, mono, 22,050 Hz, about quality 4 (libsndfile 1.2.2 through python-soundfile,
  compression level 0.6).
- Generated 2026-11-14.
