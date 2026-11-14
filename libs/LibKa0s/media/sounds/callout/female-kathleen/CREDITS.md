# Callout voice pack: female-kathleen

Forty-three spoken call-outs for `LibKa0s-Callout-1.0`: the numbers `1.ogg` to `20.ogg` and the stock
lines (`ready`, `go`, `start`, `stop`, `warning`, `error`, `done`, `finish`, `new_best`, `pause`,
`resume`, `canceled`, `pull`, `interrupt`, `move`, `defensive`, `rebuff`, `expiring`, `upgrade`,
`time_up`, `victory`, `failed`, `last_ten`). Each clip was synthesized with Piper; no person recorded
these lines.

## Voice

- Voice: Piper `en_US-kathleen-medium` (US English, female, one speaker, 22,050 Hz).
- Model: <https://huggingface.co/rhasspy/piper-voices/tree/main/en/en_US/kathleen/medium>, model card
  <https://huggingface.co/rhasspy/piper-voices/blob/main/en/en_US/kathleen/medium/MODEL_CARD>.
  The piper-voices repository is published under the MIT license.
  `en_US-kathleen-medium.onnx` SHA-256
  `173115e17ff8efb7aa895a4957fb0bccf7c6d9048d82f8c5821902a68f959cc3`.
- Dataset: the kathleen voice dataset of the Nabu Casa Voice Datasets,
  <https://github.com/OHF-Voice/voice-datasets>, collected for Home Assistant's Year of Voice by
  Nabu Casa. License: CC0 1.0 Universal (public domain dedication), text in `LICENSE-CC0-1.0.txt`.
- Base model: the voice was fine-tuned from Piper's `en_US-hifi_tts_92-medium` base model, which was
  trained on reader 92 (Cori Samuel, a LibriVox volunteer) of the Hi-Fi Multi-Speaker English TTS
  Dataset, NVIDIA Corporation, <https://www.openslr.org/109/>. License: CC BY 4.0, text in
  `LICENSE-CC-BY-4.0.txt`. Attribution: Bakhturina, Lavrukhin, Ginsburg and Zhang, "Hi-Fi
  Multi-Speaker English TTS Dataset", Interspeech 2021, <https://arxiv.org/abs/2104.01497>. Changes:
  the base model was fine-tuned on another speaker, and these clips are that model's output, trimmed
  and normalized as below.

## Generation

- Generator: piper-tts 1.8.0 (Python), <https://github.com/OHF-Voice/piper1-gpl>, with the model's own
  `noise_scale` 0.5 and `noise_w` 0.333, `length_scale` 0.85 (a little faster than the 1.0 default).
- Text: each line as a word or phrase ending in `!` (numbers as words, `last_ten` as "Ten
  seconds!"), except `pause`, `canceled` and `failed`, which end in a period.
- Post-processing: leading and trailing silence trimmed at 45 dB below the clip's peak with 15 ms
  kept on each side and a 5 ms fade, then peak-normalized to -1 dBFS.
- Encoding: Ogg Vorbis, mono, 22,050 Hz, about quality 4 (libsndfile 1.2.2 through python-soundfile,
  compression level 0.6).
- Generated 2026-11-13.
