#!/usr/bin/env python3
"""
VibeVoice Warm Server - Keeps model loaded for fast inference
Listens on HTTP port for TTS requests
"""

import os
import sys
import json
import time
import tempfile
import argparse
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlparse
import threading

# Ensure logs don't crash on Unicode (Windows console/codepage issues).
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# Add VibeVoice to path
VIBEVOICE_REPO = os.environ.get('VIBEVOICE_REPO', '/home/shkas/projects/raaz/VibeVoice')
VIBEVOICE_DEMO = os.path.join(VIBEVOICE_REPO, 'demo')
sys.path.insert(0, VIBEVOICE_REPO)
sys.path.insert(0, VIBEVOICE_DEMO)

# Globals
model = None
processor = None
voice_mapper = None
device_kind = "cpu"
torch_device = None
model_lock = threading.Lock()

CHECKPOINT = os.environ.get('VIBEVOICE_CHECKPOINT', '/home/shkas/projects/raaz/VibeVoice/checkpoints/VibeVoice-Realtime-0.5B')
DEVICE = os.environ.get('VIBEVOICE_DEVICE', 'cpu')
DEFAULT_VOICE = os.environ.get('VIBEVOICE_VOICE', 'Carter')
PORT = int(os.environ.get('VIBEVOICE_SERVER_PORT', '7860'))


def move_to_device(obj, device, dtype=None):
    import torch
    try:
        from transformers.utils import ModelOutput
    except Exception:
        ModelOutput = None
    try:
        from transformers.cache_utils import DynamicCache
    except Exception:
        DynamicCache = None

    if ModelOutput is not None and isinstance(obj, ModelOutput):
        converted = {k: move_to_device(v, device, dtype) for k, v in obj.items()}
        try:
            return obj.__class__(**converted)
        except Exception:
            return converted
    if DynamicCache is not None and isinstance(obj, DynamicCache):
        # Move cache tensors in-place to the requested device/dtype.
        if hasattr(obj, "layers"):
            for layer in obj.layers:
                if hasattr(layer, "keys") and layer.keys is not None:
                    layer.keys = move_to_device(layer.keys, device, dtype)
                if hasattr(layer, "values") and layer.values is not None:
                    layer.values = move_to_device(layer.values, device, dtype)
            return obj
        key_cache = getattr(obj, "key_cache", None)
        value_cache = getattr(obj, "value_cache", None)
        if isinstance(key_cache, list) and isinstance(value_cache, list):
            obj.key_cache = [move_to_device(v, device, dtype) for v in key_cache]
            obj.value_cache = [move_to_device(v, device, dtype) for v in value_cache]
        return obj
    if torch.is_tensor(obj):
        if dtype is not None and obj.dtype.is_floating_point:
            return obj.to(device=device, dtype=dtype)
        return obj.to(device)
    if isinstance(obj, dict):
        return {k: move_to_device(v, device, dtype) for k, v in obj.items()}
    if isinstance(obj, tuple):
        return tuple(move_to_device(v, device, dtype) for v in obj)
    if isinstance(obj, list):
        return [move_to_device(v, device, dtype) for v in obj]
    return obj


def resolve_device(device_req: str):
    import torch

    req = (device_req or "cpu").lower()

    if req == "auto":
        if torch.cuda.is_available():
            req = "cuda"
        else:
            try:
                import torch_directml
                if torch_directml.device_count() > 0:
                    return "directml", torch_directml.device(0)
            except Exception:
                pass
            if torch.backends.mps.is_available():
                req = "mps"
            else:
                req = "cpu"

    if req in ("directml", "dml"):
        try:
            import torch_directml
            if torch_directml.device_count() > 0:
                return "directml", torch_directml.device(0)
        except Exception as e:
            print(f"DirectML init failed: {e}")
        return "cpu", torch.device("cpu")

    if req == "cuda" and torch.cuda.is_available():
        return "cuda", torch.device("cuda:0")

    if req == "mps" and torch.backends.mps.is_available():
        return "mps", torch.device("mps")

    return "cpu", torch.device("cpu")


def load_model():
    """Load VibeVoice model and processor"""
    global model, processor, voice_mapper, device_kind, torch_device
    
    print(f"Loading VibeVoice model from {CHECKPOINT}...")
    print(f"Device request: {DEVICE}")
    start = time.time()
    
    from vibevoice.modular.modeling_vibevoice_streaming_inference import VibeVoiceStreamingForConditionalGenerationInference
    from vibevoice.processor.vibevoice_streaming_processor import VibeVoiceStreamingProcessor
    
    # Import VoiceMapper from demo
    from realtime_model_inference_from_file import VoiceMapper
    
    processor = VibeVoiceStreamingProcessor.from_pretrained(CHECKPOINT)
    print(f"Processor loaded in {time.time() - start:.1f}s")
    
    import torch
    device_kind, torch_device = resolve_device(DEVICE)
    print(f"Resolved device: {device_kind}")

    if device_kind == "cuda":
        torch_dtype = torch.float16
        attn_impl = "flash_attention_2"
        model = VibeVoiceStreamingForConditionalGenerationInference.from_pretrained(
            CHECKPOINT,
            torch_dtype=torch_dtype,
            device_map="cuda",
            attn_implementation=attn_impl,
        )
    else:
        torch_dtype = torch.float32 if device_kind in ("cpu", "mps") else torch.float16
        attn_impl = "sdpa"
        model = VibeVoiceStreamingForConditionalGenerationInference.from_pretrained(
            CHECKPOINT,
            torch_dtype=torch_dtype,
            device_map="cpu",
            attn_implementation=attn_impl,
        )
        if device_kind == "mps":
            model.to("mps")
        elif device_kind == "directml" and torch_device is not None:
            try:
                model = model.to(dtype=torch.float16)
                model = model.to(torch_device)
            except Exception as e:
                print(f"Warning: DirectML fp16 failed: {e}. Retrying in fp32.")
                try:
                    model = VibeVoiceStreamingForConditionalGenerationInference.from_pretrained(
                        CHECKPOINT,
                        torch_dtype=torch.float32,
                        device_map="cpu",
                        attn_implementation=attn_impl,
                    )
                    model = model.to(torch_device)
                except Exception as e2:
                    print(f"Warning: failed to move model to DirectML: {e2}. Using CPU.")
                    device_kind = "cpu"
                    torch_device = torch.device("cpu")
                    model = model.to(torch_device)

    print(f"Model loaded in {time.time() - start:.1f}s")
    
    voice_mapper = VoiceMapper()
    print(f"Voice mapper loaded. Available voices: {list(voice_mapper.voice_presets.keys())[:10]}...")
    
    print(f"VibeVoice server ready! Total load time: {time.time() - start:.1f}s")


def generate_speech(text: str, voice: str = None, cfg_scale: float = 1.5) -> bytes:
    """Generate speech from text, returns WAV bytes"""
    global model, processor, voice_mapper
    
    if voice is None:
        voice = DEFAULT_VOICE
    
    import torch
    import numpy as np
    import io
    import soundfile as sf
    
    start = time.time()
    
    with model_lock:
        # Set faster diffusion steps (default is 8192, too slow for CPU)
        model.set_ddpm_inference_steps(num_steps=5)
        
        # Get voice preset
        voice_path = voice_mapper.get_voice_path(voice)
        if voice_path is None:
            # Try with language prefix
            for lang in ['en', 'in']:
                voice_path = voice_mapper.get_voice_path(f"{lang}-{voice}")
                if voice_path:
                    break
        
        if voice_path is None:
            print(f"Warning: Voice '{voice}' not found, using first available")
            voice_path = list(voice_mapper.voice_presets.values())[0]
        
        print(f"Using voice: {voice_path}")
        
        # Load voice preset (weights_only=False for compatibility with older presets)
        voice_preset = torch.load(voice_path, map_location="cpu", weights_only=False)
        # Some environments deserialize ModelOutput as plain dicts.
        # Normalize to BaseModelOutputWithPast so HF generation cache helpers work.
        try:
            from transformers.modeling_outputs import BaseModelOutputWithPast
            if isinstance(voice_preset, dict):
                for key in ("lm", "tts_lm", "neg_lm", "neg_tts_lm"):
                    entry = voice_preset.get(key)
                    if isinstance(entry, dict):
                        voice_preset[key] = BaseModelOutputWithPast(**entry)
        except Exception:
            # If conversion fails, keep original structure; generation may still work.
            pass
        # Normalize cached past_key_values to avoid old DynamicCache pickles.
        def normalize_past_key_values(entry):
            if entry is None:
                return
            pkv = getattr(entry, "past_key_values", None)
            if pkv is None:
                return
            try:
                from transformers.cache_utils import DynamicCache
            except Exception:
                DynamicCache = None
            # Older transformers pickled DynamicCache lacks "layers" but has key_cache/value_cache lists.
            key_cache = getattr(pkv, "key_cache", None)
            value_cache = getattr(pkv, "value_cache", None)
            if key_cache is not None and value_cache is not None:
                if isinstance(key_cache, list) and isinstance(value_cache, list):
                    if len(key_cache) == len(value_cache):
                        legacy = tuple((k, v) for k, v in zip(key_cache, value_cache))
                        if DynamicCache is not None:
                            try:
                                entry.past_key_values = DynamicCache.from_legacy_cache(legacy)
                                return
                            except Exception:
                                entry.past_key_values = legacy
                                return
                        entry.past_key_values = legacy
                        return
            # Some dumps store cache as dicts.
            if isinstance(pkv, dict):
                key_cache = pkv.get("key_cache")
                value_cache = pkv.get("value_cache")
                if isinstance(key_cache, list) and isinstance(value_cache, list):
                    if len(key_cache) == len(value_cache):
                        legacy = tuple((k, v) for k, v in zip(key_cache, value_cache))
                        if DynamicCache is not None:
                            try:
                                entry.past_key_values = DynamicCache.from_legacy_cache(legacy)
                                return
                            except Exception:
                                entry.past_key_values = legacy
                                return
                        entry.past_key_values = legacy

        if isinstance(voice_preset, dict):
            for key in ("lm", "tts_lm", "neg_lm", "neg_tts_lm"):
                normalize_past_key_values(voice_preset.get(key))
        if device_kind != "cpu" and torch_device is not None:
            cast_dtype = torch.float16 if device_kind == "directml" else None
            voice_preset = move_to_device(voice_preset, torch_device, cast_dtype)
        
        # Prepare inputs using the correct VibeVoice API
        inputs = processor.process_input_with_cached_prompt(
            text=text,
            cached_prompt=voice_preset,
            padding=True,
            return_tensors="pt",
            return_attention_mask=True,
        )

        if device_kind != "cpu" and torch_device is not None:
            cast_dtype = torch.float16 if device_kind == "directml" else None
            inputs = move_to_device(inputs, torch_device, cast_dtype)
        
        # Generate
        import copy
        with torch.no_grad():
            outputs = model.generate(
                **inputs,
                max_new_tokens=None,
                cfg_scale=cfg_scale,
                tokenizer=processor.tokenizer,
                generation_config={'do_sample': False},
                verbose=True,
                all_prefilled_outputs=copy.deepcopy(voice_preset) if voice_preset is not None else None,
            )
        
        # Get audio using processor's save_audio method
        # Create temp file and use processor to save
        with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp:
            tmp_path = tmp.name
        
        processor.save_audio(
            outputs.speech_outputs[0],
            output_path=tmp_path,
        )
        
        # Read back the file
        with open(tmp_path, 'rb') as f:
            buffer = io.BytesIO(f.read())
        buffer.seek(0)
        
        # Clean up temp file
        import os
        os.unlink(tmp_path)
        
        # Get audio info for duration calculation
        audio_data = buffer.getvalue()
        duration = len(audio_data) / 24000 / 2
        gen_time = time.time() - start
        print(f"Generated {duration:.1f}s audio in {gen_time:.1f}s (RTF: {gen_time/duration:.2f}x)")
        
        return audio_data


class TTSHandler(BaseHTTPRequestHandler):
    """HTTP request handler for TTS"""
    
    def do_GET(self):
        """Handle GET requests - health check"""
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'ok', 'model': 'vibevoice'}).encode())
        else:
            self.send_response(404)
            self.end_headers()
    
    def do_POST(self):
        """Handle POST requests - TTS generation"""
        try:
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length).decode('utf-8')
            
            # Parse request
            if self.headers.get('Content-Type') == 'application/json':
                data = json.loads(body)
            else:
                data = parse_qs(body)
                data = {k: v[0] for k, v in data.items()}
            
            text = data.get('text', '')
            voice = data.get('voice', DEFAULT_VOICE)
            cfg_scale = float(data.get('cfg_scale', 1.5))
            
            if not text:
                self.send_response(400)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({'error': 'text is required'}).encode())
                return
            
            preview = text[:50]
            try:
                preview = preview.encode("ascii", "backslashreplace").decode("ascii")
            except Exception:
                preview = "<unprintable>"
            print(f"Request: text='{preview}...' voice={voice}")
            
            # Generate speech
            wav_bytes = generate_speech(text, voice, cfg_scale)
            
            # Send response
            self.send_response(200)
            self.send_header('Content-Type', 'audio/wav')
            self.send_header('Content-Length', len(wav_bytes))
            self.end_headers()
            self.wfile.write(wav_bytes)
            
        except Exception as e:
            print(f"Error: {e}")
            import traceback
            traceback.print_exc()
            self.send_response(500)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'error': str(e)}).encode())
    
    def log_message(self, format, *args):
        """Custom log format"""
        print(f"[{self.log_date_time_string()}] {args[0]}")


def main():
    parser = argparse.ArgumentParser(description='VibeVoice Warm Server')
    parser.add_argument('--port', type=int, default=PORT, help='Port to listen on')
    parser.add_argument('--host', default='127.0.0.1', help='Host to bind to')
    args = parser.parse_args()
    
    # Load model
    load_model()
    
    # Start server
    server = HTTPServer((args.host, args.port), TTSHandler)
    print(f"\nVibeVoice server listening on http://{args.host}:{args.port}")
    print(f"Health check: http://{args.host}:{args.port}/health")
    print(f"TTS endpoint: POST http://{args.host}:{args.port}/tts")
    print("\nPress Ctrl+C to stop\n")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()


if __name__ == '__main__':
    main()
