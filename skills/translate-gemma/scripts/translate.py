#!/usr/bin/env python3
import argparse
import json
import os
import sys
import urllib.error
import urllib.request


def read_text(args: argparse.Namespace) -> str:
    if args.text:
        return args.text
    if args.text_file:
        with open(args.text_file, "r", encoding="utf-8") as handle:
            return handle.read()
    if not sys.stdin.isatty():
        return sys.stdin.read()
    return ""


def build_prompt(target: str, text: str) -> str:
    return (
        f"Translate the following text to {target}. "
        "Only return the translated text, no explanations.\n\n"
        f"{text}"
    )




def main() -> int:
    parser = argparse.ArgumentParser(
        description="Translate text to English using TranslateGemma via Ollama.",
    )
    parser.add_argument("--text", help="Text to translate.")
    parser.add_argument("--text-file", help="Path to file containing text to translate.")
    parser.add_argument("--out", help="Write translated text to this file.")
    parser.add_argument(
        "--model",
        default=os.environ.get("TRANSLATE_GEMMA_MODEL", "translate-gemma:4b"),
        help="Ollama model id.",
    )
    parser.add_argument(
        "--target",
        default=os.environ.get("TRANSLATE_GEMMA_TARGET", "English"),
        help="Target language.",
    )
    parser.add_argument(
        "--base-url",
        default=os.environ.get("TRANSLATE_GEMMA_OLLAMA_URL", "http://127.0.0.1:11434"),
        help="Ollama base URL.",
    )
    parser.add_argument(
        "--temperature",
        type=float,
        default=float(os.environ.get("TRANSLATE_GEMMA_TEMPERATURE", "0.1")),
        help="Sampling temperature.",
    )
    parser.add_argument(
        "--timeout-seconds",
        type=int,
        default=int(os.environ.get("TRANSLATE_GEMMA_TIMEOUT_SECONDS", "30")),
        help="HTTP timeout in seconds.",
    )
    args = parser.parse_args()

    text = read_text(args).strip()
    if not text:
        parser.error("Provide --text, --text-file, or stdin.")

    payload = {
        "model": args.model,
        "prompt": build_prompt(args.target, text),
        "stream": False,
        "options": {"temperature": args.temperature},
    }
    url = args.base_url.rstrip("/") + "/api/generate"
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=args.timeout_seconds) as response:
            body = response.read().decode("utf-8")
    except urllib.error.HTTPError as err:
        sys.stderr.write(f"TranslateGemma HTTP error: {err.code}\n")
        return 2
    except urllib.error.URLError as err:
        sys.stderr.write(f"TranslateGemma connection error: {err}\n")
        return 2

    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        sys.stderr.write("TranslateGemma returned invalid JSON.\n")
        return 2

    translation = str(data.get("response", "")).strip()
    if not translation:
        sys.stderr.write("TranslateGemma returned empty output.\n")
        return 2

    if args.out:
        out_dir = os.path.dirname(args.out)
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
        with open(args.out, "w", encoding="utf-8") as handle:
            handle.write(translation)
        print(args.out)
    else:
        print(translation)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
