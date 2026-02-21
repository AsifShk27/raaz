---
name: translate-gemma
description: Local translation to English using TranslateGemma via Ollama.
metadata: {"openclaw":{"requires":{"bins":["ollama","python3"]}}}
---

# TranslateGemma (Local Translation)

Translate text to English on-device using TranslateGemma served by Ollama.

## Quick setup

1. Install Ollama: https://ollama.ai
2. Pull a model (use 4B for speed, 12B for quality):
   - `ollama pull translate-gemma:4b`
   - `ollama pull translate-gemma:12b`
3. Warm the model (keeps it hot for low latency):
   - `ollama run translate-gemma:4b "hello"`

## Script

- `{baseDir}/scripts/translate.py`

## Usage

```bash
# Translate inline text (stdout)
{baseDir}/scripts/translate.py --text "Hola, como estas?"

# Translate a file (stdout)
{baseDir}/scripts/translate.py --text-file /tmp/input.txt

# Write output to a file
{baseDir}/scripts/translate.py --text "Bonjour" --out /tmp/en.txt
```

## Environment

- `TRANSLATE_GEMMA_MODEL` (default: `translate-gemma:4b`)
- `TRANSLATE_GEMMA_TARGET` (default: `English`)
- `TRANSLATE_GEMMA_OLLAMA_URL` (default: `http://127.0.0.1:11434`)
- `TRANSLATE_GEMMA_TEMPERATURE` (default: `0.1`)

## OpenClaw integration (voice-to-voice)

```json5
{
  tools: {
    audio: {
      transcription: {
        args: ["--model", "base", "{{MediaPath}}"],
        timeoutSeconds: 45
      },
      translation: {
        command: ["/path/to/skills/translate-gemma/scripts/translate.py", "--text", "{{Transcript}}"],
        timeoutSeconds: 20
      }
    }
  }
}
```

Notes:
- Use `--text-file {{TranscriptFile}}` if you want to avoid very long command lines.
- The translated text replaces `Body` and `Transcript`; the original stays in `OriginalTranscript`.

## AMD GPU (RX 6800)

TranslateGemma runs on GPU only if **Ollama** is running with GPU acceleration.
For AMD, use Ollama on **Windows** with AMD GPU support and keep
`TRANSLATE_GEMMA_OLLAMA_URL` pointing at it (default `http://127.0.0.1:11434`
works from WSL).
