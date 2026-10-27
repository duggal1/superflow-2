# Generated audio fixtures

The repository does not store generated audio binaries. Create deterministic 16 kHz mono PCM16 signal fixtures with:

```sh
make gen-fixture OUTPUT=/tmp/superflow-audio.wav SECONDS=60
```

These non-speech fixtures exercise format conversion, sample counts, journal rotation and replay. They are not ASR accuracy fixtures. ASR and meeting goldens must use licensed speech recordings or macOS speech synthesis and must document their source and expected transcript.
