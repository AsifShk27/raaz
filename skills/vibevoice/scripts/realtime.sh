#!/bin/bash
# VibeVoice Real-time Streaming TTS Demo
# Launches a WebSocket server for real-time speech synthesis

set -e

VIBEVOICE_CHECKPOINT="${VIBEVOICE_CHECKPOINT:-}"
VIBEVOICE_DEVICE="${VIBEVOICE_DEVICE:-cuda}"
PORT="${VIBEVOICE_WEBSOCKET_PORT:-10000}"
PYTHON="${VIBEVOICE_PYTHON:-/usr/bin/python3.12}"

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Start VibeVoice real-time streaming TTS WebSocket server.

Options:
    --port PORT     WebSocket port (default: 10000)
    --help          Show this help

Environment variables:
    VIBEVOICE_CHECKPOINT        Path to VibeVoice-Realtime checkpoint
    VIBEVOICE_DEVICE            Device to use (cuda/cpu)
    VIBEVOICE_WEBSOCKET_PORT    WebSocket port

The server accepts JSON messages:
    {"type": "synthesize", "text": "Hello world", "speaker_id": 0}

And streams audio chunks back in real-time.

Example:
    $(basename "$0") --port 10000
EOF
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --port)
            PORT="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

if [[ -z "$VIBEVOICE_CHECKPOINT" ]]; then
    echo "Error: VIBEVOICE_CHECKPOINT environment variable not set"
    echo "For realtime mode, use the VibeVoice-Realtime checkpoint"
    exit 1
fi

echo "Starting VibeVoice Real-time TTS server..."
echo "Checkpoint: $VIBEVOICE_CHECKPOINT"
echo "Device: $VIBEVOICE_DEVICE"
echo "Port: $PORT"
echo ""
echo "Press Ctrl+C to stop"

# Start the realtime demo
export VIBEVOICE_WEBSOCKET_PORT="$PORT"
$PYTHON - << 'PYTHON_EOF'
import sys
import os
import asyncio
import websockets
import json
import numpy as np

checkpoint = os.environ.get("VIBEVOICE_CHECKPOINT", "")
device = os.environ.get("VIBEVOICE_DEVICE", "cuda")
port = int(os.environ.get("VIBEVOICE_WEBSOCKET_PORT", "10000"))

sys.path.insert(0, "/home/shkas/projects/raaz/VibeVoice")

try:
    from vibevoice import VibeVoiceInference

    print("Loading VibeVoice-Realtime model...")
    infer = VibeVoiceInference(
        checkpoint=checkpoint,
        device=device
    )
    print("Model loaded successfully!")

    async def handle_client(websocket):
        print(f"Client connected")
        try:
            async for message in websocket:
                try:
                    data = json.loads(message)

                    if data.get("type") == "synthesize":
                        text = data.get("text", "")
                        speaker_id = data.get("speaker_id", 0)

                        print(f"Synthesizing: {text[:50]}...")

                        # Generate with streaming
                        audio_stream = infer.generate(
                            text=text,
                            max_audio_length_sec=300,
                            stream=True,
                            speaker_id=speaker_id
                        )

                        # Send audio chunks
                        for chunk in audio_stream:
                            # Convert to int16 for WAV compatibility
                            chunk_int16 = (chunk * 32767).astype(np.int16)
                            await websocket.send(chunk_int16.tobytes())

                        await websocket.send(json.dumps({"type": "done"}))

                    else:
                        await websocket.send(json.dumps({"error": "Unknown message type"}))

                except Exception as e:
                    await websocket.send(json.dumps({"error": str(e)}))

        except websockets.exceptions.ConnectionClosed:
            print("Client disconnected")

    async def main():
        async with websockets.serve(handle_client, "0.0.0.0", port):
            print(f"Server running on ws://0.0.0.0:{port}")
            await asyncio.Future()  # Run forever

    asyncio.run(main())

except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    import traceback
    traceback.print_exc()
    sys.exit(1)
PYTHON_EOF
