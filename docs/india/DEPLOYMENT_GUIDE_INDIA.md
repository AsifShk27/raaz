# Clawdbot Deployment Guide for Indian Small Businesses

## Complete Setup Guide: Cloud, On-Premises, and Hybrid Deployments

**Version:** 1.0
**Date:** January 2026
**Target Audience:** Developers deploying Clawdbot for Indian SMBs

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Prerequisites](#2-prerequisites)
3. [Option 1: Fully Cloud Deployment](#3-option-1-fully-cloud-deployment)
4. [Option 2: Fully On-Premises Deployment](#4-option-2-fully-on-premises-deployment)
5. [Option 3: Hybrid Deployments](#5-option-3-hybrid-deployments)
6. [Voice Configuration (Hindi TTS/ASR)](#6-voice-configuration-hindi-ttsasr)
7. [WhatsApp Integration](#7-whatsapp-integration)
8. [Multi-Tenant SaaS Setup](#8-multi-tenant-saas-setup)
9. [Monitoring & Maintenance](#9-monitoring--maintenance)
10. [Troubleshooting](#10-troubleshooting)
11. [On-Premises LLM Inference (GPU Setup)](#11-on-premises-llm-inference-gpu-setup)

---

## 1. Architecture Overview

### Current Clawdbot Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        CLAWDBOT ARCHITECTURE                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         CLAWDBOT CORE                                │   │
│  │                                                                      │   │
│  │  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐               │   │
│  │  │  Channels   │   │   Agents    │   │    Tools    │               │   │
│  │  │  - WhatsApp │   │  - Default  │   │  - Audio    │               │   │
│  │  │  - Telegram │   │  - Custom   │   │  - Search   │               │   │
│  │  │  - Discord  │   │             │   │  - Browse   │               │   │
│  │  │  - Slack    │   │             │   │             │               │   │
│  │  └──────┬──────┘   └──────┬──────┘   └──────┬──────┘               │   │
│  │         │                 │                 │                       │   │
│  │         └─────────────────┼─────────────────┘                       │   │
│  │                           │                                          │   │
│  │                    ┌──────▼──────┐                                  │   │
│  │                    │   Gateway   │                                  │   │
│  │                    │  (Router)   │                                  │   │
│  │                    └──────┬──────┘                                  │   │
│  │                           │                                          │   │
│  └───────────────────────────┼──────────────────────────────────────────┘   │
│                              │                                               │
│              ┌───────────────┼───────────────┐                              │
│              │               │               │                              │
│              ▼               ▼               ▼                              │
│  ┌───────────────┐   ┌───────────────┐   ┌───────────────┐                 │
│  │  LLM Provider │   │ Voice (TTS)   │   │ Voice (ASR)   │                 │
│  │  - Claude API │   │ - Azure TTS   │   │ - Whisper     │                 │
│  │  - OpenAI API │   │ - ElevenLabs  │   │ - Azure ASR   │                 │
│  │  - Local LLM  │   │ - Piper Local │   │ - Local       │                 │
│  │  - Ollama     │   │               │   │               │                 │
│  └───────────────┘   └───────────────┘   └───────────────┘                 │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Key Insight: No Code Changes Needed!

Clawdbot already supports:
- ✅ **Local LLMs** via OpenAI-compatible APIs (Ollama, LM Studio, vLLM)
- ✅ **Custom TTS/ASR** via CLI commands with templates
- ✅ **Multiple providers** with fallback chains
- ✅ **Configuration-only changes** for different deployment modes

---

## 2. Prerequisites

### 2.1 For All Deployments

```bash
# Node.js 20+ required
node --version  # Should be 20.x or higher

# Git
git --version

# Clone Clawdbot
git clone https://github.com/clawdbot/clawdbot.git
cd clawdbot

# Install dependencies
npm install

# Build
npm run build
```

### 2.2 API Keys (Cloud Deployments)

| Service | Environment Variable | Get From |
|---------|---------------------|----------|
| Claude API | `ANTHROPIC_API_KEY` | https://console.anthropic.com |
| OpenAI API | `OPENAI_API_KEY` | https://platform.openai.com |
| Azure Speech | `AZURE_SPEECH_KEY` | https://portal.azure.com |
| Azure Region | `AZURE_SPEECH_REGION` | Azure Portal (e.g., `centralindia`) |
| ElevenLabs | `ELEVENLABS_API_KEY` | https://elevenlabs.io |

### 2.3 Hardware Requirements

| Deployment | Minimum | Recommended |
|------------|---------|-------------|
| **Fully Cloud** | 1 vCPU, 1GB RAM | 2 vCPU, 2GB RAM |
| **Hybrid (Cloud LLM)** | 2 vCPU, 4GB RAM | 4 vCPU, 8GB RAM |
| **Fully On-Prem** | 4 vCPU, 8GB RAM + NPU | 8 vCPU, 16GB RAM + GPU |

---

## 3. Option 1: Fully Cloud Deployment

### 3.1 Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        FULLY CLOUD DEPLOYMENT                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  CUSTOMER                      CLOUD SERVER                  CLOUD APIS     │
│  ────────                      ────────────                  ──────────     │
│                                                                              │
│  ┌─────────┐                  ┌─────────────────┐          ┌─────────────┐ │
│  │WhatsApp │◀───Internet────▶│   CLAWDBOT      │─────────▶│ Claude API  │ │
│  │  User   │                  │   (Node.js)     │          └─────────────┘ │
│  └─────────┘                  │                 │                           │
│                               │  ┌───────────┐ │          ┌─────────────┐ │
│                               │  │  Baileys  │ │─────────▶│ Azure TTS   │ │
│                               │  │ (WhatsApp)│ │          │ (Hindi)     │ │
│                               │  └───────────┘ │          └─────────────┘ │
│                               │                 │                           │
│                               └─────────────────┘          ┌─────────────┐ │
│                                      │                     │ Azure ASR   │ │
│                                      └────────────────────▶│ (Whisper)   │ │
│                                                            └─────────────┘ │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Server Setup (DigitalOcean/AWS)

```bash
# Create Ubuntu 22.04 server (2GB RAM minimum)
# SSH into server

# Install Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install PM2 for process management
sudo npm install -g pm2

# Install FFmpeg (for audio processing)
sudo apt-get install -y ffmpeg

# Clone and build Clawdbot
git clone https://github.com/clawdbot/clawdbot.git
cd clawdbot
npm install
npm run build
```

### 3.3 Configuration File

Create `~/.clawdbot/clawdbot.json`:

```json5
{
  // Identity for Indian market
  "identity": {
    "name": "सहायक",  // "Sahayak" - Hindi for Assistant
    "theme": "helpful Hindi-speaking business assistant",
    "emoji": "🙏"
  },

  // Agent configuration - Claude for best Hindi support
  "agents": {
    "defaults": {
      "workspace": "~/clawdbot-workspace",
      "model": {
        "primary": "anthropic/claude-sonnet-4",
        "fallbacks": ["openai/gpt-4o-mini"]
      },
      "systemPrompt": "You are a helpful assistant for Indian small businesses. Respond in the same language the user writes in. If they write in Hindi (Devanagari or Roman), respond in Hindi. If they mix Hindi and English (Hinglish), respond similarly. Be polite, use 'ji' for respect. Keep responses concise and helpful for WhatsApp."
    }
  },

  // Audio configuration for Hindi voice
  "audio": {
    "reply": {
      "command": [
        "node",
        "/opt/clawdbot/scripts/azure-tts.js",
        "--voice", "hi-IN-SwaraNeural",
        "--output", "{{ReplyAudioPath}}",
        "--text", "{{ReplyText}}"
      ],
      "timeoutSeconds": 30,
      "voiceOnly": false
    }
  },

  // Transcription using Azure Speech
  "tools": {
    "audio": {
      "transcription": {
        "args": [
          "node",
          "/opt/clawdbot/scripts/azure-asr.js",
          "--language", "hi-IN",
          "{{MediaPath}}"
        ],
        "timeoutSeconds": 60
      }
    }
  },

  // WhatsApp channel configuration
  "channels": {
    "whatsapp": {
      "enabled": true,
      "accounts": {
        "default": {
          "authDir": "~/.clawdbot/whatsapp-auth"
        }
      },
      "dmPolicy": "open",  // Accept messages from anyone
      "groupPolicy": "open",  // Respond in groups
      "actions": {
        "reactions": true
      }
    }
  },

  // Logging
  "logging": {
    "level": "info",
    "file": "~/.clawdbot/logs/clawdbot.log"
  }
}
```

### 3.4 Azure TTS Script

Create `/opt/clawdbot/scripts/azure-tts.js`:

```javascript
#!/usr/bin/env node
/**
 * Azure TTS Script for Hindi Voice Synthesis
 * Usage: node azure-tts.js --voice hi-IN-SwaraNeural --output /path/to/output.mp3 --text "नमस्ते"
 */

const sdk = require('microsoft-cognitiveservices-speech-sdk');
const fs = require('fs');
const path = require('path');

// Parse arguments
const args = process.argv.slice(2);
const getArg = (name) => {
  const idx = args.indexOf(name);
  return idx !== -1 ? args[idx + 1] : null;
};

const voice = getArg('--voice') || 'hi-IN-SwaraNeural';
const outputPath = getArg('--output');
const text = getArg('--text');

if (!outputPath || !text) {
  console.error('Usage: azure-tts.js --voice <voice> --output <path> --text <text>');
  process.exit(1);
}

// Azure configuration from environment
const speechKey = process.env.AZURE_SPEECH_KEY;
const speechRegion = process.env.AZURE_SPEECH_REGION || 'centralindia';

if (!speechKey) {
  console.error('AZURE_SPEECH_KEY environment variable not set');
  process.exit(1);
}

async function synthesize() {
  const speechConfig = sdk.SpeechConfig.fromSubscription(speechKey, speechRegion);
  speechConfig.speechSynthesisVoiceName = voice;
  speechConfig.speechSynthesisOutputFormat = sdk.SpeechSynthesisOutputFormat.Audio16Khz32KBitRateMonoMp3;

  const audioConfig = sdk.AudioConfig.fromAudioFileOutput(outputPath);
  const synthesizer = new sdk.SpeechSynthesizer(speechConfig, audioConfig);

  return new Promise((resolve, reject) => {
    synthesizer.speakTextAsync(
      text,
      (result) => {
        if (result.reason === sdk.ResultReason.SynthesizingAudioCompleted) {
          console.log(`MEDIA:${outputPath}`);
          resolve();
        } else {
          reject(new Error(`Speech synthesis failed: ${result.errorDetails}`));
        }
        synthesizer.close();
      },
      (error) => {
        synthesizer.close();
        reject(error);
      }
    );
  });
}

synthesize().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
```

### 3.5 Azure ASR Script

Create `/opt/clawdbot/scripts/azure-asr.js`:

```javascript
#!/usr/bin/env node
/**
 * Azure Speech-to-Text Script for Hindi
 * Usage: node azure-asr.js --language hi-IN /path/to/audio.ogg
 */

const sdk = require('microsoft-cognitiveservices-speech-sdk');
const fs = require('fs');

const args = process.argv.slice(2);
const getArg = (name) => {
  const idx = args.indexOf(name);
  return idx !== -1 ? args[idx + 1] : null;
};

const language = getArg('--language') || 'hi-IN';
const audioPath = args[args.length - 1];

if (!audioPath || !fs.existsSync(audioPath)) {
  console.error('Audio file not found');
  process.exit(1);
}

const speechKey = process.env.AZURE_SPEECH_KEY;
const speechRegion = process.env.AZURE_SPEECH_REGION || 'centralindia';

if (!speechKey) {
  console.error('AZURE_SPEECH_KEY not set');
  process.exit(1);
}

async function transcribe() {
  const speechConfig = sdk.SpeechConfig.fromSubscription(speechKey, speechRegion);
  speechConfig.speechRecognitionLanguage = language;

  // Enable auto language detection for multilingual input
  const autoDetectConfig = sdk.AutoDetectSourceLanguageConfig.fromLanguages([
    'hi-IN',  // Hindi
    'en-IN',  // English (India)
    'ta-IN',  // Tamil
    'te-IN',  // Telugu
  ]);

  const audioConfig = sdk.AudioConfig.fromWavFileInput(fs.readFileSync(audioPath));
  const recognizer = new sdk.SpeechRecognizer(speechConfig, audioConfig);

  return new Promise((resolve, reject) => {
    recognizer.recognizeOnceAsync(
      (result) => {
        if (result.reason === sdk.ResultReason.RecognizedSpeech) {
          // Output transcript to stdout (Clawdbot reads this)
          console.log(result.text);
          resolve();
        } else if (result.reason === sdk.ResultReason.NoMatch) {
          console.log('[No speech detected]');
          resolve();
        } else {
          reject(new Error(`Recognition failed: ${result.errorDetails}`));
        }
        recognizer.close();
      },
      (error) => {
        recognizer.close();
        reject(error);
      }
    );
  });
}

transcribe().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
```

### 3.6 Install Azure SDK

```bash
cd /opt/clawdbot/scripts
npm init -y
npm install microsoft-cognitiveservices-speech-sdk
```

### 3.7 Environment Variables

Create `/etc/environment.d/clawdbot.conf`:

```bash
ANTHROPIC_API_KEY=sk-ant-xxxxxxxxxxxxx
AZURE_SPEECH_KEY=xxxxxxxxxxxxxxxxxxxxxx
AZURE_SPEECH_REGION=centralindia
```

Or add to `~/.bashrc`:

```bash
export ANTHROPIC_API_KEY="sk-ant-xxxxxxxxxxxxx"
export AZURE_SPEECH_KEY="xxxxxxxxxxxxxxxxxxxxxx"
export AZURE_SPEECH_REGION="centralindia"
```

### 3.8 Start Clawdbot

```bash
# First time - Link WhatsApp
cd ~/clawdbot
npm run gateway

# Scan QR code with WhatsApp on phone
# Settings → Linked Devices → Link a Device

# After linking, run with PM2
pm2 start npm --name "clawdbot" -- run gateway
pm2 save
pm2 startup
```

### 3.9 Cost Estimate (Fully Cloud)

| Component | Monthly Cost |
|-----------|--------------|
| DigitalOcean Droplet (2GB) | ₹800 |
| Claude API (1000 conversations) | ₹2,000 |
| Azure Speech TTS | ₹500 |
| Azure Speech ASR | ₹500 |
| **Total** | **₹3,800/month** |

---

## 4. Option 2: Fully On-Premises Deployment

### 4.1 Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     FULLY ON-PREMISES DEPLOYMENT                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  RANI'S HOME / SHOP                                                         │
│  ─────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│  ┌─────────────┐                 ┌─────────────────────────────────────┐   │
│  │  Rani's     │      WiFi      │   RASPBERRY PI 5 + HAILO-8          │   │
│  │  Phone      │◀──────────────▶│                                      │   │
│  │  (WhatsApp) │                 │  ┌─────────────────────────────┐   │   │
│  └─────────────┘                 │  │        CLAWDBOT             │   │   │
│                                  │  │                             │   │   │
│                                  │  │  Baileys ◀──▶ WhatsApp     │   │   │
│                                  │  │     │                       │   │   │
│                                  │  │     ▼                       │   │   │
│                                  │  │  ┌───────────────────┐     │   │   │
│                                  │  │  │ Ollama            │     │   │   │
│                                  │  │  │ (Qwen-3 4B)       │     │   │   │
│                                  │  │  │ LOCAL LLM         │     │   │   │
│                                  │  │  └───────────────────┘     │   │   │
│                                  │  │     │                       │   │   │
│                                  │  │     ▼                       │   │   │
│                                  │  │  ┌───────────────────┐     │   │   │
│                                  │  │  │ Piper TTS         │     │   │   │
│                                  │  │  │ (Hindi Voice)     │     │   │   │
│                                  │  │  │ LOCAL             │     │   │   │
│                                  │  │  └───────────────────┘     │   │   │
│                                  │  │     │                       │   │   │
│                                  │  │     ▼                       │   │   │
│                                  │  │  ┌───────────────────┐     │   │   │
│                                  │  │  │ Whisper           │     │   │   │
│                                  │  │  │ (Speech-to-Text)  │     │   │   │
│                                  │  │  │ LOCAL             │     │   │   │
│                                  │  │  └───────────────────┘     │   │   │
│                                  │  │                             │   │   │
│                                  │  └─────────────────────────────┘   │   │
│                                  │                                      │   │
│                                  │  ALL PROCESSING LOCAL               │   │
│                                  │  Internet only for WhatsApp         │   │
│                                  └─────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Hardware Setup

#### Option A: Raspberry Pi 5 + Hailo-8

```bash
# Hardware shopping list (India)
# 1. Raspberry Pi 5 (8GB) - ₹7,500 (Robocraze, ThingBits)
# 2. Hailo-8L AI Kit - ₹7,000 (Direct from Hailo or distributors)
# 3. NVMe SSD 256GB - ₹2,500 (Amazon)
# 4. Active cooling case - ₹800 (Amazon)
# 5. 27W USB-C power supply - ₹500 (Official)
# Total: ₹18,300
```

#### Option B: Mini PC (Intel N100)

```bash
# Hardware shopping list
# 1. Beelink Mini S12 Pro (N100, 16GB, 500GB) - ₹18,000 (Amazon)
# OR GMKtec N100 - ₹15,000 (Amazon)
# Total: ₹15,000-18,000
```

### 4.3 Raspberry Pi Setup

```bash
# Flash Raspberry Pi OS (64-bit) to SD card
# Boot and SSH in

# Update system
sudo apt update && sudo apt upgrade -y

# Install Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install FFmpeg
sudo apt-get install -y ffmpeg

# Install Ollama
curl -fsSL https://ollama.com/install.sh | sh

# Pull Qwen-3 model (best Hindi support among small models)
ollama pull qwen2.5:3b

# Install Whisper.cpp for ASR
sudo apt-get install -y build-essential
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp
make
# Download Hindi-optimized model
./models/download-ggml-model.sh small

# Install Piper TTS
pip3 install piper-tts
# Download Hindi voice
piper --download-voice hi_IN-swara-medium
```

### 4.4 Configuration File (On-Prem)

Create `~/.clawdbot/clawdbot.json`:

```json5
{
  "identity": {
    "name": "सहायक",
    "theme": "helpful Hindi assistant for local business",
    "emoji": "🙏"
  },

  // Use Ollama for local LLM
  "agents": {
    "defaults": {
      "workspace": "~/clawdbot-workspace",
      "model": {
        "primary": "ollama/qwen2.5:3b"
      },
      "systemPrompt": "You are a helpful assistant for a small Indian business. Respond in Hindi if the user writes in Hindi, or in English if they write in English. Be concise - this is WhatsApp. Use respectful language (ji, aap). Help with orders, inquiries, and basic questions."
    }
  },

  // Configure Ollama as provider
  "models": {
    "mode": "merge",
    "providers": {
      "ollama": {
        "baseUrl": "http://127.0.0.1:11434/v1",
        "apiKey": "ollama",  // Ollama doesn't need real key
        "api": "openai-responses",
        "models": [
          {
            "id": "qwen2.5:3b",
            "name": "Qwen 2.5 3B",
            "reasoning": false,
            "input": ["text"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
            "contextWindow": 32768,
            "maxTokens": 4096
          },
          {
            "id": "qwen2.5:7b",
            "name": "Qwen 2.5 7B",
            "reasoning": false,
            "input": ["text"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
            "contextWindow": 32768,
            "maxTokens": 4096
          }
        ]
      }
    }
  },

  // Local Piper TTS
  "audio": {
    "reply": {
      "command": [
        "piper",
        "--model", "/home/pi/.local/share/piper/hi_IN-swara-medium.onnx",
        "--output_file", "{{ReplyAudioPath}}",
        "--text", "{{ReplyText}}"
      ],
      "timeoutSeconds": 30,
      "voiceOnly": false
    }
  },

  // Local Whisper ASR
  "tools": {
    "audio": {
      "transcription": {
        "args": [
          "/home/pi/whisper.cpp/main",
          "-m", "/home/pi/whisper.cpp/models/ggml-small.bin",
          "-l", "hi",
          "-f", "{{MediaPath}}",
          "--output-txt"
        ],
        "timeoutSeconds": 120  // Local processing is slower
      }
    }
  },

  // WhatsApp configuration
  "channels": {
    "whatsapp": {
      "enabled": true,
      "accounts": {
        "default": {
          "authDir": "~/.clawdbot/whatsapp-auth"
        }
      },
      "dmPolicy": "open",
      "groupPolicy": "open"
    }
  },

  "logging": {
    "level": "info",
    "file": "~/.clawdbot/logs/clawdbot.log"
  }
}
```

### 4.5 Piper TTS Hindi Voice Setup

```bash
# Download Hindi voice model
mkdir -p ~/.local/share/piper
cd ~/.local/share/piper

# Download Swara (Hindi female voice)
wget https://huggingface.co/rhasspy/piper-voices/resolve/main/hi/hi_IN/swara/medium/hi_IN-swara-medium.onnx
wget https://huggingface.co/rhasspy/piper-voices/resolve/main/hi/hi_IN/swara/medium/hi_IN-swara-medium.onnx.json

# Test voice
echo "नमस्ते, मैं आपकी सहायता के लिए हूं" | piper \
  --model ~/.local/share/piper/hi_IN-swara-medium.onnx \
  --output_file test.wav
aplay test.wav
```

### 4.6 Whisper Setup for Hindi

```bash
cd ~/whisper.cpp

# Convert audio to WAV (WhatsApp sends OGG)
# Create wrapper script: /usr/local/bin/whisper-transcribe.sh

cat > /usr/local/bin/whisper-transcribe.sh << 'EOF'
#!/bin/bash
INPUT="$1"
TEMP_WAV="/tmp/whisper_input_$$.wav"

# Convert to WAV
ffmpeg -i "$INPUT" -ar 16000 -ac 1 -c:a pcm_s16le "$TEMP_WAV" -y 2>/dev/null

# Run Whisper
~/whisper.cpp/main \
  -m ~/whisper.cpp/models/ggml-small.bin \
  -l hi \
  -f "$TEMP_WAV" \
  --no-timestamps \
  -otxt 2>/dev/null

# Output is in TEMP_WAV.txt
cat "${TEMP_WAV}.txt" 2>/dev/null

# Cleanup
rm -f "$TEMP_WAV" "${TEMP_WAV}.txt"
EOF

chmod +x /usr/local/bin/whisper-transcribe.sh
```

Update config to use wrapper:

```json5
"tools": {
  "audio": {
    "transcription": {
      "args": [
        "/usr/local/bin/whisper-transcribe.sh",
        "{{MediaPath}}"
      ],
      "timeoutSeconds": 120
    }
  }
}
```

### 4.7 Start Services

```bash
# Start Ollama service
sudo systemctl enable ollama
sudo systemctl start ollama

# Verify Ollama is running
curl http://localhost:11434/v1/models

# Start Clawdbot
cd ~/clawdbot
npm run gateway

# For production, use PM2
pm2 start npm --name "clawdbot" -- run gateway
pm2 save
pm2 startup
```

### 4.8 Cost Estimate (On-Prem)

| Component | One-Time Cost | Monthly Cost |
|-----------|---------------|--------------|
| Raspberry Pi 5 + Hailo-8 | ₹18,300 | - |
| OR Mini PC | ₹15,000-18,000 | - |
| Electricity | - | ₹200-300 |
| Internet (existing) | - | ₹0 |
| **Total** | **₹15,000-18,300** | **₹200-300** |

---

## 5. Option 3: Hybrid Deployments

### 5.1 Hybrid Config A: Cloud LLM + Cloud Voice

**Best for: Maximum quality, moderate cost**

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                   HYBRID A: CLOUD LLM + CLOUD VOICE                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  LOCAL DEVICE (Mini PC)              CLOUD SERVICES                         │
│  ─────────────────────               ──────────────                         │
│                                                                              │
│  ┌─────────────────────┐            ┌─────────────────────┐                │
│  │     CLAWDBOT        │            │     CLAUDE API      │                │
│  │                     │◀──────────▶│     (LLM)           │                │
│  │  • Baileys          │            │     Best Quality    │                │
│  │  • Message routing  │            └─────────────────────┘                │
│  │  • Session mgmt     │                                                    │
│  │  • Local caching    │            ┌─────────────────────┐                │
│  │                     │◀──────────▶│     AZURE TTS       │                │
│  └─────────────────────┘            │     (Hindi Voice)   │                │
│                                     │     Natural Sound   │                │
│                                     └─────────────────────┘                │
│                                                                              │
│                                     ┌─────────────────────┐                │
│                                     │     AZURE ASR       │                │
│                                     │     (Hindi STT)     │                │
│                                     └─────────────────────┘                │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Configuration (`~/.clawdbot/clawdbot.json`):**

```json5
{
  "identity": {
    "name": "सहायक",
    "theme": "helpful Hindi business assistant",
    "emoji": "🙏"
  },

  // Cloud Claude for best quality
  "agents": {
    "defaults": {
      "workspace": "~/clawdbot-workspace",
      "model": {
        "primary": "anthropic/claude-sonnet-4",
        "fallbacks": ["openai/gpt-4o-mini"]
      },
      "systemPrompt": "You are a helpful assistant for Indian small businesses. Respond in the same language the user writes in. Be concise for WhatsApp. Use respectful Hindi honorifics (ji, aap)."
    }
  },

  // Cloud Azure TTS
  "audio": {
    "reply": {
      "command": [
        "node", "/opt/scripts/azure-tts.js",
        "--voice", "hi-IN-SwaraNeural",
        "--output", "{{ReplyAudioPath}}",
        "--text", "{{ReplyText}}"
      ],
      "timeoutSeconds": 30,
      "voiceOnly": false
    }
  },

  // Cloud Azure ASR
  "tools": {
    "audio": {
      "transcription": {
        "args": [
          "node", "/opt/scripts/azure-asr.js",
          "--language", "hi-IN",
          "{{MediaPath}}"
        ],
        "timeoutSeconds": 60
      }
    }
  },

  "channels": {
    "whatsapp": {
      "enabled": true,
      "dmPolicy": "open",
      "groupPolicy": "open"
    }
  }
}
```

**Cost: ₹8,000 device + ₹2,500-3,500/month**

---

### 5.2 Hybrid Config B: Cloud LLM + Local Voice

**Best for: Good quality, lower monthly cost**

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                   HYBRID B: CLOUD LLM + LOCAL VOICE                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  LOCAL DEVICE (Mini PC / Pi)         CLOUD SERVICES                         │
│  ──────────────────────────          ──────────────                         │
│                                                                              │
│  ┌─────────────────────┐            ┌─────────────────────┐                │
│  │     CLAWDBOT        │            │     CLAUDE API      │                │
│  │                     │◀──────────▶│     (LLM)           │                │
│  │  • Baileys          │            │     Best Quality    │                │
│  │  • Message routing  │            └─────────────────────┘                │
│  │                     │                                                    │
│  │  ┌───────────────┐ │                                                    │
│  │  │ LOCAL WHISPER │ │            (No cloud voice APIs)                   │
│  │  │ (ASR)         │ │                                                    │
│  │  └───────────────┘ │                                                    │
│  │                     │                                                    │
│  │  ┌───────────────┐ │                                                    │
│  │  │ LOCAL PIPER   │ │                                                    │
│  │  │ (TTS Hindi)   │ │                                                    │
│  │  └───────────────┘ │                                                    │
│  │                     │                                                    │
│  └─────────────────────┘                                                    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Configuration:**

```json5
{
  "identity": {
    "name": "सहायक",
    "theme": "helpful Hindi business assistant",
    "emoji": "🙏"
  },

  // Cloud Claude for best quality
  "agents": {
    "defaults": {
      "workspace": "~/clawdbot-workspace",
      "model": {
        "primary": "anthropic/claude-sonnet-4",
        "fallbacks": ["openai/gpt-4o-mini"]
      },
      "systemPrompt": "You are a helpful assistant for Indian small businesses. Respond in Hindi or English based on user's language. Be concise for WhatsApp."
    }
  },

  // LOCAL Piper TTS
  "audio": {
    "reply": {
      "command": [
        "piper",
        "--model", "/home/user/.local/share/piper/hi_IN-swara-medium.onnx",
        "--output_file", "{{ReplyAudioPath}}",
        "--text", "{{ReplyText}}"
      ],
      "timeoutSeconds": 30,
      "voiceOnly": false
    }
  },

  // LOCAL Whisper ASR
  "tools": {
    "audio": {
      "transcription": {
        "args": [
          "/usr/local/bin/whisper-transcribe.sh",
          "{{MediaPath}}"
        ],
        "timeoutSeconds": 120
      }
    }
  },

  "channels": {
    "whatsapp": {
      "enabled": true,
      "dmPolicy": "open",
      "groupPolicy": "open"
    }
  }
}
```

**Cost: ₹15,000 device + ₹1,500-2,500/month**

---

### 5.3 Hybrid Config C: Local LLM + Cloud Voice

**Best for: Privacy-focused, good voice quality**

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                   HYBRID C: LOCAL LLM + CLOUD VOICE                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  LOCAL DEVICE                        CLOUD SERVICES                         │
│  ────────────                        ──────────────                         │
│                                                                              │
│  ┌─────────────────────┐            ┌─────────────────────┐                │
│  │     CLAWDBOT        │            │     AZURE TTS       │                │
│  │                     │◀──────────▶│     (Hindi Voice)   │                │
│  │  • Baileys          │            │     Natural Sound   │                │
│  │  • Message routing  │            └─────────────────────┘                │
│  │                     │                                                    │
│  │  ┌───────────────┐ │            (Messages processed locally)           │
│  │  │ LOCAL OLLAMA  │ │            (Only voice sent to cloud)             │
│  │  │ Qwen-3 4B     │ │                                                    │
│  │  │ (LLM)         │ │                                                    │
│  │  └───────────────┘ │                                                    │
│  │                     │                                                    │
│  │  ┌───────────────┐ │                                                    │
│  │  │ LOCAL WHISPER │ │                                                    │
│  │  │ (ASR)         │ │                                                    │
│  │  └───────────────┘ │                                                    │
│  │                     │                                                    │
│  └─────────────────────┘                                                    │
│                                                                              │
│  PRIVACY: Message content stays local, only final reply goes to TTS        │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Configuration:**

```json5
{
  "identity": {
    "name": "सहायक",
    "theme": "helpful Hindi business assistant",
    "emoji": "🙏"
  },

  // LOCAL Ollama LLM
  "agents": {
    "defaults": {
      "workspace": "~/clawdbot-workspace",
      "model": {
        "primary": "ollama/qwen2.5:7b"
      },
      "systemPrompt": "You are a helpful assistant for Indian small businesses. Respond in Hindi or English based on user's language. Be concise for WhatsApp."
    }
  },

  // Ollama provider config
  "models": {
    "mode": "merge",
    "providers": {
      "ollama": {
        "baseUrl": "http://127.0.0.1:11434/v1",
        "apiKey": "ollama",
        "api": "openai-responses",
        "models": [
          {
            "id": "qwen2.5:7b",
            "name": "Qwen 2.5 7B",
            "reasoning": false,
            "input": ["text"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
            "contextWindow": 32768,
            "maxTokens": 4096
          }
        ]
      }
    }
  },

  // CLOUD Azure TTS (only voice output goes to cloud)
  "audio": {
    "reply": {
      "command": [
        "node", "/opt/scripts/azure-tts.js",
        "--voice", "hi-IN-SwaraNeural",
        "--output", "{{ReplyAudioPath}}",
        "--text", "{{ReplyText}}"
      ],
      "timeoutSeconds": 30,
      "voiceOnly": false
    }
  },

  // LOCAL Whisper ASR
  "tools": {
    "audio": {
      "transcription": {
        "args": [
          "/usr/local/bin/whisper-transcribe.sh",
          "{{MediaPath}}"
        ],
        "timeoutSeconds": 120
      }
    }
  },

  "channels": {
    "whatsapp": {
      "enabled": true,
      "dmPolicy": "open",
      "groupPolicy": "open"
    }
  }
}
```

**Cost: ₹18,000 device + ₹500-1,000/month**

---

### 5.4 Hybrid Config D: Full Local + Cloud Fallback

**Best for: Maximum flexibility, works offline**

```
┌─────────────────────────────────────────────────────────────────────────────┐
│              HYBRID D: LOCAL PRIMARY + CLOUD FALLBACK                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  LOCAL DEVICE                        CLOUD (FALLBACK ONLY)                  │
│  ────────────                        ────────────────────                   │
│                                                                              │
│  ┌─────────────────────┐            ┌─────────────────────┐                │
│  │     CLAWDBOT        │            │     CLAUDE API      │                │
│  │                     │            │     (Complex Qs)    │                │
│  │  ┌───────────────┐ │            └─────────────────────┘                │
│  │  │ LOCAL OLLAMA  │ │                     ▲                              │
│  │  │ (Primary LLM) │ │─── Complex Q? ──────┘                              │
│  │  └───────────────┘ │                                                    │
│  │         │          │                                                    │
│  │         │ Simple Q │                                                    │
│  │         ▼          │                                                    │
│  │  ┌───────────────┐ │            ┌─────────────────────┐                │
│  │  │ LOCAL PIPER   │ │            │     AZURE TTS       │                │
│  │  │ (Primary TTS) │ │── Need ───▶│     (Quality TTS)   │                │
│  │  └───────────────┘ │   Quality? └─────────────────────┘                │
│  │                     │                                                    │
│  │  ┌───────────────┐ │                                                    │
│  │  │ LOCAL WHISPER │ │                                                    │
│  │  │ (ASR)         │ │                                                    │
│  │  └───────────────┘ │                                                    │
│  │                     │                                                    │
│  └─────────────────────┘                                                    │
│                                                                              │
│  LOGIC:                                                                      │
│  • Simple questions → Local Ollama + Local Piper                           │
│  • Complex questions → Claude API                                           │
│  • Internet down → Everything local                                         │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**This requires a custom routing script. Create `/opt/scripts/smart-router.js`:**

```javascript
#!/usr/bin/env node
/**
 * Smart Router - Routes to local or cloud based on complexity
 */

const { execSync } = require('child_process');

const message = process.argv[2];

// Simple heuristic for routing
function isComplex(msg) {
  // Route to cloud if:
  // - Message is long (> 200 chars)
  // - Contains code-related words
  // - Asks for detailed explanation
  // - Multiple questions

  const complexIndicators = [
    msg.length > 200,
    /explain|detail|why|how does|compare|analyze/i.test(msg),
    /code|program|script|function/i.test(msg),
    (msg.match(/\?/g) || []).length > 1,  // Multiple questions
    /और.*और|aur.*aur/i.test(msg),  // Multiple "and" (Hindi)
  ];

  return complexIndicators.filter(Boolean).length >= 2;
}

// Check if internet is available
function hasInternet() {
  try {
    execSync('ping -c 1 8.8.8.8', { timeout: 2000, stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

// Route decision
const useCloud = isComplex(message) && hasInternet();

// Output routing decision (Clawdbot reads this)
console.log(JSON.stringify({
  route: useCloud ? 'cloud' : 'local',
  reason: useCloud ? 'complex_query' : 'simple_query'
}));
```

**For Config D, you'll need a custom Clawdbot modification or use agent bindings:**

```json5
{
  "identity": {
    "name": "सहायक",
    "emoji": "🙏"
  },

  // Define two agents
  "agents": {
    "defaults": {
      "workspace": "~/clawdbot-workspace"
    },
    "list": [
      {
        "id": "local",
        "name": "Local Assistant",
        "model": { "primary": "ollama/qwen2.5:3b" },
        "systemPrompt": "You are a helpful Hindi assistant. Be concise."
      },
      {
        "id": "cloud",
        "name": "Cloud Assistant",
        "model": {
          "primary": "anthropic/claude-sonnet-4",
          "fallbacks": ["ollama/qwen2.5:3b"]  // Fallback to local if cloud fails
        },
        "systemPrompt": "You are a helpful Hindi assistant. Provide detailed answers."
      }
    ]
  },

  // Ollama provider
  "models": {
    "mode": "merge",
    "providers": {
      "ollama": {
        "baseUrl": "http://127.0.0.1:11434/v1",
        "apiKey": "ollama",
        "api": "openai-responses",
        "models": [
          {
            "id": "qwen2.5:3b",
            "name": "Qwen 2.5 3B",
            "reasoning": false,
            "input": ["text"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
            "contextWindow": 32768,
            "maxTokens": 4096
          }
        ]
      }
    }
  },

  // Use fallbacks for automatic routing
  // Primary: Claude (cloud)
  // Fallback: Ollama (local) - used when cloud fails
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-sonnet-4",
        "fallbacks": ["ollama/qwen2.5:3b"]
      }
    }
  },

  // Local TTS with cloud quality option
  "audio": {
    "reply": {
      "command": [
        "/opt/scripts/smart-tts.sh",
        "{{ReplyAudioPath}}",
        "{{ReplyText}}"
      ],
      "timeoutSeconds": 45,
      "voiceOnly": false
    }
  },

  "tools": {
    "audio": {
      "transcription": {
        "args": [
          "/usr/local/bin/whisper-transcribe.sh",
          "{{MediaPath}}"
        ],
        "timeoutSeconds": 120
      }
    }
  },

  "channels": {
    "whatsapp": {
      "enabled": true,
      "dmPolicy": "open",
      "groupPolicy": "open"
    }
  }
}
```

**Smart TTS Script (`/opt/scripts/smart-tts.sh`):**

```bash
#!/bin/bash
# Smart TTS - Uses Azure if available, falls back to Piper

OUTPUT_PATH="$1"
TEXT="$2"

# Check if Azure is available
if [ -n "$AZURE_SPEECH_KEY" ] && ping -c 1 8.8.8.8 &>/dev/null; then
  # Use Azure TTS
  node /opt/scripts/azure-tts.js \
    --voice "hi-IN-SwaraNeural" \
    --output "$OUTPUT_PATH" \
    --text "$TEXT"
else
  # Use local Piper
  echo "$TEXT" | piper \
    --model ~/.local/share/piper/hi_IN-swara-medium.onnx \
    --output_file "$OUTPUT_PATH"
  echo "MEDIA:$OUTPUT_PATH"
fi
```

**Cost: ₹18,000 device + ₹1,000-2,000/month**

---

## 6. Voice Configuration (Hindi TTS/ASR)

### 6.1 Available Hindi Voices

#### Azure TTS (Cloud)

| Voice ID | Gender | Style | Best For |
|----------|--------|-------|----------|
| `hi-IN-SwaraNeural` | Female | Natural, friendly | Customer service |
| `hi-IN-MadhurNeural` | Male | Professional | Business |
| `hi-IN-AnanyaNeural` | Female | Young, energetic | Casual |

#### Piper TTS (Local)

| Voice | Gender | Quality | Size |
|-------|--------|---------|------|
| `hi_IN-swara-medium` | Female | Good | 50MB |
| `hi_IN-swara-high` | Female | Better | 100MB |

### 6.2 Voice Configuration Examples

**Azure TTS with SSML (Advanced):**

```javascript
// /opt/scripts/azure-tts-ssml.js
const ssml = `
<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="hi-IN">
  <voice name="hi-IN-SwaraNeural">
    <prosody rate="0.9" pitch="+5%">
      ${text}
    </prosody>
  </voice>
</speak>
`;
```

**Multiple Language Support:**

```json5
"audio": {
  "reply": {
    "command": [
      "/opt/scripts/multilang-tts.sh",
      "{{ReplyAudioPath}}",
      "{{ReplyText}}"
    ],
    "timeoutSeconds": 30
  }
}
```

```bash
#!/bin/bash
# /opt/scripts/multilang-tts.sh
# Detects language and uses appropriate voice

OUTPUT="$1"
TEXT="$2"

# Simple language detection
if echo "$TEXT" | grep -qP '[\x{0900}-\x{097F}]'; then
  VOICE="hi-IN-SwaraNeural"  # Hindi (Devanagari)
elif echo "$TEXT" | grep -qP '[\x{0B80}-\x{0BFF}]'; then
  VOICE="ta-IN-PallaviNeural"  # Tamil
elif echo "$TEXT" | grep -qP '[\x{0C00}-\x{0C7F}]'; then
  VOICE="te-IN-ShrutiNeural"  # Telugu
else
  VOICE="en-IN-NeerjaNeural"  # English (India)
fi

node /opt/scripts/azure-tts.js --voice "$VOICE" --output "$OUTPUT" --text "$TEXT"
```

---

## 7. WhatsApp Integration

### 7.1 First-Time Setup

```bash
# Start Clawdbot
cd ~/clawdbot
npm run gateway

# You'll see a QR code in terminal
# On your phone: WhatsApp → Settings → Linked Devices → Link a Device
# Scan the QR code

# Credentials saved to ~/.clawdbot/whatsapp-auth/
```

### 7.2 WhatsApp Configuration Options

```json5
"channels": {
  "whatsapp": {
    "enabled": true,

    // Multiple accounts (for SaaS)
    "accounts": {
      "rani_tiffin": {
        "authDir": "~/.clawdbot/whatsapp-auth/rani"
      },
      "kumar_clinic": {
        "authDir": "~/.clawdbot/whatsapp-auth/kumar"
      }
    },

    // Who can message
    "dmPolicy": "open",  // "open" | "allowlist" | "pairing"

    // Group behavior
    "groupPolicy": "open",  // "open" | "allowlist" | "disabled"

    // Only respond to specific groups
    "allowGroups": [
      "120363xxxxx@g.us"  // Group JID
    ],

    // Require @ mention in groups
    "requireMention": false,

    // Auto-react to messages
    "actions": {
      "reactions": true
    },

    // Message prefix (optional)
    "prefix": "!",  // Only respond to "!help" etc.

    // Self-chat mode (respond to your own messages)
    "selfChatMode": false
  }
}
```

### 7.3 Group Message Handling

```json5
// Only respond in specific groups
"channels": {
  "whatsapp": {
    "groupPolicy": "allowlist",
    "allowGroups": [
      "120363123456789@g.us",  // Society Group 1
      "120363987654321@g.us"   // Society Group 2
    ]
  }
}
```

### 7.4 Handling Different Message Types

Clawdbot handles:
- ✅ Text messages
- ✅ Voice notes (transcribed)
- ✅ Images (with vision models)
- ✅ Documents (text extraction)
- ✅ Polls
- ✅ Reactions

---

## 8. Multi-Tenant SaaS Setup

### 8.1 Architecture for Multiple Businesses

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      MULTI-TENANT SaaS ARCHITECTURE                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         CLAWDBOT SERVER                              │   │
│  │                                                                      │   │
│  │  ┌─────────────────────────────────────────────────────────────┐   │   │
│  │  │                    TENANT MANAGER                            │   │   │
│  │  │                                                              │   │   │
│  │  │  Tenant 1: Rani Tiffin     Tenant 2: Kumar Clinic           │   │   │
│  │  │  ┌──────────────────┐      ┌──────────────────┐             │   │   │
│  │  │  │ WhatsApp Account │      │ WhatsApp Account │             │   │   │
│  │  │  │ Config: menu.json│      │ Config: clinic.js│             │   │   │
│  │  │  │ Agent: food      │      │ Agent: health    │             │   │   │
│  │  │  └──────────────────┘      └──────────────────┘             │   │   │
│  │  │                                                              │   │   │
│  │  │  Tenant 3: Sharma Tuition  Tenant N: ...                    │   │   │
│  │  │  ┌──────────────────┐      ┌──────────────────┐             │   │   │
│  │  │  │ WhatsApp Account │      │ WhatsApp Account │             │   │   │
│  │  │  │ Config: edu.json │      │ Config: ...      │             │   │   │
│  │  │  │ Agent: tutor     │      │ Agent: ...       │             │   │   │
│  │  │  └──────────────────┘      └──────────────────┘             │   │   │
│  │  │                                                              │   │   │
│  │  └─────────────────────────────────────────────────────────────┘   │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 8.2 Per-Tenant Configuration

Create separate config files for each tenant:

**`/opt/clawdbot/tenants/rani_tiffin.json5`:**

```json5
{
  "identity": {
    "name": "रानी टिफिन सर्विस",
    "emoji": "🍱"
  },

  "agents": {
    "defaults": {
      "systemPrompt": `You are the AI assistant for Rani's Tiffin Service.

MENU (Update daily):
- Chicken Biryani: ₹150
- Veg Pulao: ₹100
- Dal Rice: ₹80
- Raita: ₹30

TIMINGS:
- Orders: 8 AM - 11 AM
- Delivery: 12 PM - 2 PM

DELIVERY AREAS:
- Tower A, B, C
- Within 2km radius

RULES:
1. Take orders politely in Hindi or English
2. Confirm: items, quantity, address, total
3. Payment: UPI to 98765@paytm
4. Send voice confirmation for orders

RESPONSES:
- Keep short for WhatsApp
- Use 🙏 for greetings
- Confirm orders with ✅`
    }
  },

  "channels": {
    "whatsapp": {
      "accounts": {
        "default": {
          "authDir": "/opt/clawdbot/tenants/rani_tiffin/whatsapp-auth"
        }
      }
    }
  }
}
```

**`/opt/clawdbot/tenants/kumar_clinic.json5`:**

```json5
{
  "identity": {
    "name": "Dr. Kumar Clinic",
    "emoji": "🏥"
  },

  "agents": {
    "defaults": {
      "systemPrompt": `You are the AI receptionist for Dr. Kumar's Clinic.

SERVICES:
- General Consultation: ₹500
- Follow-up: ₹300
- Health Checkup: ₹2000

TIMINGS:
- Morning: 9 AM - 1 PM
- Evening: 5 PM - 8 PM
- Closed: Sundays

RULES:
1. Help with appointment booking
2. Answer basic queries about services
3. For medical advice, ask them to visit
4. Be empathetic and professional
5. Collect: Name, Phone, Preferred time

NEVER:
- Give medical diagnosis
- Prescribe medicines
- Share other patient info`
    }
  },

  "channels": {
    "whatsapp": {
      "accounts": {
        "default": {
          "authDir": "/opt/clawdbot/tenants/kumar_clinic/whatsapp-auth"
        }
      }
    }
  }
}
```

### 8.3 Running Multiple Tenants

**Option 1: Multiple Clawdbot Instances (Simple)**

```bash
# Start each tenant as separate process
pm2 start npm --name "rani_tiffin" -- run gateway -- --config /opt/clawdbot/tenants/rani_tiffin.json5
pm2 start npm --name "kumar_clinic" -- run gateway -- --config /opt/clawdbot/tenants/kumar_clinic.json5
pm2 start npm --name "sharma_tuition" -- run gateway -- --config /opt/clawdbot/tenants/sharma_tuition.json5
```

**Option 2: Single Instance with Multiple Accounts**

```json5
// Main clawdbot.json5
{
  "channels": {
    "whatsapp": {
      "accounts": {
        "rani_tiffin": {
          "authDir": "/opt/clawdbot/tenants/rani_tiffin/whatsapp-auth"
        },
        "kumar_clinic": {
          "authDir": "/opt/clawdbot/tenants/kumar_clinic/whatsapp-auth"
        },
        "sharma_tuition": {
          "authDir": "/opt/clawdbot/tenants/sharma_tuition/whatsapp-auth"
        }
      }
    }
  },

  // Route to different agents based on account
  "bindings": [
    {
      "match": { "account": "rani_tiffin" },
      "agent": "food_assistant"
    },
    {
      "match": { "account": "kumar_clinic" },
      "agent": "clinic_assistant"
    },
    {
      "match": { "account": "sharma_tuition" },
      "agent": "tutor_assistant"
    }
  ],

  "agents": {
    "list": [
      {
        "id": "food_assistant",
        "systemPrompt": "You are Rani Tiffin assistant..."
      },
      {
        "id": "clinic_assistant",
        "systemPrompt": "You are Dr. Kumar Clinic assistant..."
      },
      {
        "id": "tutor_assistant",
        "systemPrompt": "You are Sharma Tuition assistant..."
      }
    ]
  }
}
```

---

## 9. Monitoring & Maintenance

### 9.1 PM2 Monitoring

```bash
# View all processes
pm2 list

# View logs
pm2 logs clawdbot

# Monitor CPU/Memory
pm2 monit

# Restart on crash
pm2 start npm --name "clawdbot" -- run gateway --max-restarts 10
```

### 9.2 Health Check Script

```bash
#!/bin/bash
# /opt/scripts/health-check.sh

# Check if Clawdbot is running
if ! pm2 pid clawdbot > /dev/null 2>&1; then
  echo "Clawdbot not running, restarting..."
  pm2 restart clawdbot
  exit 1
fi

# Check if Ollama is running (for on-prem)
if ! curl -s http://localhost:11434/api/tags > /dev/null; then
  echo "Ollama not responding, restarting..."
  sudo systemctl restart ollama
fi

# Check WhatsApp connection
if ! grep -q "Connection open" ~/.clawdbot/logs/clawdbot.log | tail -100; then
  echo "WhatsApp may be disconnected"
  # Send alert (optional)
fi

echo "All services healthy"
```

Add to crontab:

```bash
# Check every 5 minutes
*/5 * * * * /opt/scripts/health-check.sh >> /var/log/clawdbot-health.log 2>&1
```

### 9.3 Log Rotation

```bash
# /etc/logrotate.d/clawdbot
/home/user/.clawdbot/logs/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    create 0644 user user
}
```

---

## 10. Troubleshooting

### 10.1 Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| QR code not showing | Terminal issue | Try `npm run gateway -- --qr-terminal` |
| WhatsApp disconnects | Session expired | Delete auth dir, re-scan QR |
| Slow responses | LLM timeout | Increase timeout, use faster model |
| Voice not working | FFmpeg missing | `sudo apt install ffmpeg` |
| Hindi garbled | Encoding issue | Ensure UTF-8 in all files |
| Ollama slow | Not enough RAM | Use smaller model (3B vs 7B) |

### 10.2 Debug Mode

```bash
# Run with debug logging
DEBUG=* npm run gateway

# Or set in config
{
  "logging": {
    "level": "debug"
  }
}
```

### 10.3 Testing Voice

```bash
# Test TTS
echo "नमस्ते, यह एक टेस्ट है" | piper \
  --model ~/.local/share/piper/hi_IN-swara-medium.onnx \
  --output_file test.wav
aplay test.wav

# Test ASR
/usr/local/bin/whisper-transcribe.sh test_audio.ogg
```

### 10.4 Testing LLM

```bash
# Test Ollama
curl http://localhost:11434/api/generate -d '{
  "model": "qwen2.5:3b",
  "prompt": "नमस्ते, आप कैसे हैं?",
  "stream": false
}'

# Test Claude API
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "content-type: application/json" \
  -d '{
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 100,
    "messages": [{"role": "user", "content": "नमस्ते"}]
  }'
```

---

## 11. On-Premises LLM Inference (GPU Setup)

### 11.1 Why On-Prem LLM?

For SaaS providers serving 50+ customers, running your own LLM inference can significantly reduce costs while improving privacy and latency.

**Benefits:**
- **Cost Savings**: After initial investment, per-query cost drops to near-zero
- **Privacy**: Customer conversations never leave your server
- **Latency**: Local inference can be faster than cloud API round-trips
- **No Rate Limits**: Handle unlimited concurrent conversations
- **Offline Capability**: Works without internet (except WhatsApp connection)

### 11.2 Hardware Options (India Pricing - January 2026)

#### GPU Options

| GPU | VRAM | Max Model Size | Price (India) | Best For |
|-----|------|----------------|---------------|----------|
| **RTX 3060 12GB** | 12GB | 7B-8B | ₹25,000-30,000 | Budget setup, 10-50 customers |
| **RTX 4060 Ti 16GB** | 16GB | 13B-14B | ₹45,000-50,000 | Small business, 50-100 customers |
| **RTX 4070 Ti 12GB** | 12GB | 7B-8B | ₹60,000-70,000 | Faster 7B inference |
| **RTX 4070 Ti Super 16GB** | 16GB | 13B-14B | ₹75,000-85,000 | Production 14B |
| **RTX 4080 16GB** | 16GB | 13B-14B | ₹1,10,000-1,20,000 | High throughput |
| **RTX 4090 24GB** | 24GB | 32B-34B | ₹1,50,000-1,70,000 | Premium quality |
| **2x RTX 4090 (NVLink)** | 48GB | 70B | ₹3,20,000+ | Enterprise, Claude-level quality |

#### Model Size to VRAM Mapping

| Model Size | VRAM Required (Q4) | VRAM Required (Q8) | VRAM Required (FP16) |
|------------|--------------------|--------------------|----------------------|
| **3B** | 2GB | 4GB | 6GB |
| **7B** | 4GB | 8GB | 14GB |
| **8B** | 5GB | 9GB | 16GB |
| **13B/14B** | 8GB | 14GB | 28GB |
| **32B/34B** | 18GB | 34GB | 68GB |
| **70B** | 40GB | 70GB | 140GB |

**Quantization Explanation:**
- **Q4**: 4-bit quantization - smallest, ~5-10% quality loss
- **Q8**: 8-bit quantization - good balance, ~2-5% quality loss
- **FP16**: Full precision - best quality, needs most VRAM

### 11.3 Recommended Models for Hindi

| Model | Size | Hindi Quality | Speed | Best For |
|-------|------|---------------|-------|----------|
| **Qwen 2.5 3B** | 3B | Good | Very Fast | Budget Pi/Mini PC |
| **Qwen 2.5 7B** | 7B | Very Good | Fast | Small business |
| **Qwen 2.5 14B** | 14B | Excellent | Medium | Production |
| **Qwen 2.5 32B** | 32B | Outstanding | Slower | Premium |
| **Qwen 2.5 72B** | 72B | Near-Claude | Slow | Enterprise |
| **Llama 3.1 8B** | 8B | Good | Fast | Alternative |
| **Llama 3.1 70B** | 70B | Excellent | Slow | Alternative enterprise |
| **Mistral 7B** | 7B | Moderate | Fast | English-heavy use |

**Recommendation for Hindi:** Qwen 2.5 series has the best multilingual support including Hindi, Hinglish, and regional languages.

### 11.4 Complete Server Builds (India)

#### Budget Build: ₹50,000-60,000
```
- CPU: Intel i5-12400 or AMD Ryzen 5 5600 - ₹12,000
- Motherboard: B660/B550 - ₹8,000
- RAM: 32GB DDR4 - ₹6,000
- GPU: RTX 3060 12GB - ₹28,000
- SSD: 500GB NVMe - ₹3,000
- PSU: 650W 80+ Bronze - ₹4,000
- Case: Basic ATX - ₹2,000

Total: ~₹63,000
Model: Qwen 2.5 7B (Q8)
Capacity: 50-100 customers
```

#### Mid-Range Build: ₹1,10,000-1,30,000
```
- CPU: Intel i5-13400 or AMD Ryzen 7 5800X - ₹18,000
- Motherboard: B760/B550 - ₹12,000
- RAM: 64GB DDR4 - ₹12,000
- GPU: RTX 4070 Ti Super 16GB - ₹80,000
- SSD: 1TB NVMe - ₹6,000
- PSU: 750W 80+ Gold - ₹7,000
- Case: Mid-tower with airflow - ₹4,000

Total: ~₹1,39,000
Model: Qwen 2.5 14B (Q8)
Capacity: 100-300 customers
```

#### High-End Build: ₹2,50,000-3,00,000
```
- CPU: Intel i7-13700K or AMD Ryzen 9 5900X - ₹30,000
- Motherboard: Z790/X570 - ₹20,000
- RAM: 64GB DDR5 - ₹18,000
- GPU: RTX 4090 24GB - ₹1,65,000
- SSD: 2TB NVMe - ₹10,000
- PSU: 1000W 80+ Platinum - ₹12,000
- Case: Full tower with cooling - ₹8,000

Total: ~₹2,63,000
Model: Qwen 2.5 32B (Q8) or 72B (Q4)
Capacity: 300-500+ customers
```

### 11.5 Cost Comparison: Cloud vs On-Prem

#### Cloud API Costs (per 1000 conversations/month)

| Service | Cost per 1K tokens | Avg conversation | Monthly Cost |
|---------|-------------------|------------------|--------------|
| Claude Sonnet 4 | $3/$15 (in/out) | ~2K tokens | ₹2,000-3,000 |
| GPT-4o | $2.50/$10 | ~2K tokens | ₹1,500-2,500 |
| GPT-4o-mini | $0.15/$0.60 | ~2K tokens | ₹150-250 |

**For 100 customers × 30 conversations/month = 3000 conversations:**
- Claude Sonnet: ₹6,000-9,000/month
- GPT-4o: ₹4,500-7,500/month
- GPT-4o-mini: ₹450-750/month

#### On-Prem Costs (after initial investment)

| Setup | Initial Cost | Monthly (Electricity) | Cost per 1K convos |
|-------|--------------|----------------------|---------------------|
| Budget (RTX 3060) | ₹63,000 | ₹800-1,200 | ~₹0.30 |
| Mid-range (4070 Ti) | ₹1,39,000 | ₹1,000-1,500 | ~₹0.40 |
| High-end (4090) | ₹2,63,000 | ₹1,500-2,500 | ~₹0.60 |

### 11.6 Break-Even Analysis

#### Scenario: 100 Customers, 30 conversations/customer/month

| Comparison | Cloud (Claude) | On-Prem (Budget) |
|------------|----------------|------------------|
| **Month 1** | ₹7,000 | ₹63,000 + ₹1,000 = ₹64,000 |
| **Month 2** | ₹14,000 | ₹65,000 |
| **Month 3** | ₹21,000 | ₹66,000 |
| **Month 4** | ₹28,000 | ₹67,000 |
| **Month 6** | ₹42,000 | ₹69,000 |
| **Month 9** | ₹63,000 | ₹72,000 |
| **Month 10** | ₹70,000 | ₹73,000 ← **Break-even** |
| **Month 12** | ₹84,000 | ₹75,000 |
| **Year 2** | ₹1,68,000 | ₹87,000 |

**Break-even: ~10 months for budget setup with 100 customers**

#### Scenario: 300 Customers

| Comparison | Cloud (Claude) | On-Prem (Mid-range) |
|------------|----------------|---------------------|
| **Month 1** | ₹21,000 | ₹1,39,000 + ₹1,500 = ₹1,40,500 |
| **Month 3** | ₹63,000 | ₹1,44,000 |
| **Month 6** | ₹1,26,000 | ₹1,48,500 |
| **Month 7** | ₹1,47,000 | ₹1,50,000 ← **Break-even** |
| **Month 12** | ₹2,52,000 | ₹1,57,500 |

**Break-even: ~7 months for mid-range setup with 300 customers**

### 11.7 Inference Server Setup

#### Option A: Ollama (Recommended for Simplicity)

```bash
# Install Ollama
curl -fsSL https://ollama.com/install.sh | sh

# Pull models
ollama pull qwen2.5:7b      # 7B model
ollama pull qwen2.5:14b     # 14B model (if VRAM allows)

# Start server (runs on port 11434)
ollama serve

# Test
curl http://localhost:11434/api/generate -d '{
  "model": "qwen2.5:7b",
  "prompt": "नमस्ते, आज का मेनू क्या है?",
  "stream": false
}'
```

**Clawdbot Configuration for Ollama:**

```json5
{
  "models": {
    "mode": "merge",
    "providers": {
      "ollama": {
        "baseUrl": "http://127.0.0.1:11434/v1",
        "apiKey": "ollama",
        "api": "openai-responses",
        "models": [
          {
            "id": "qwen2.5:7b",
            "name": "Qwen 2.5 7B",
            "reasoning": false,
            "input": ["text"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
            "contextWindow": 32768,
            "maxTokens": 4096
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "ollama/qwen2.5:7b"
      }
    }
  }
}
```

#### Option B: vLLM (High Performance, Production)

```bash
# Install vLLM
pip install vllm

# Start server with GPU optimization
python -m vllm.entrypoints.openai.api_server \
  --model Qwen/Qwen2.5-7B-Instruct \
  --dtype auto \
  --api-key "your-local-key" \
  --host 0.0.0.0 \
  --port 8000 \
  --max-model-len 32768 \
  --gpu-memory-utilization 0.9

# With tensor parallelism for multi-GPU
python -m vllm.entrypoints.openai.api_server \
  --model Qwen/Qwen2.5-72B-Instruct \
  --tensor-parallel-size 2 \
  --dtype auto
```

**Clawdbot Configuration for vLLM:**

```json5
{
  "models": {
    "mode": "merge",
    "providers": {
      "vllm": {
        "baseUrl": "http://127.0.0.1:8000/v1",
        "apiKey": "your-local-key",
        "api": "openai-responses",
        "models": [
          {
            "id": "Qwen/Qwen2.5-7B-Instruct",
            "name": "Qwen 2.5 7B (vLLM)",
            "reasoning": false,
            "input": ["text"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
            "contextWindow": 32768,
            "maxTokens": 4096
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "vllm/Qwen/Qwen2.5-7B-Instruct"
      }
    }
  }
}
```

#### Option C: LM Studio (Easy GUI Setup)

1. Download LM Studio from https://lmstudio.ai/
2. Download Qwen 2.5 model from the built-in browser
3. Start local server (API tab → Start Server)
4. Server runs on `http://localhost:1234/v1`

**Clawdbot Configuration:**

```json5
{
  "models": {
    "mode": "merge",
    "providers": {
      "lmstudio": {
        "baseUrl": "http://127.0.0.1:1234/v1",
        "apiKey": "lm-studio",
        "api": "openai-responses",
        "models": [
          {
            "id": "qwen2.5-7b-instruct",
            "name": "Qwen 2.5 7B (LM Studio)",
            "reasoning": false,
            "input": ["text"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
            "contextWindow": 32768,
            "maxTokens": 4096
          }
        ]
      }
    }
  }
}
```

### 11.8 Performance Optimization

#### Ollama Optimization

```bash
# Set environment variables for better performance
export OLLAMA_NUM_PARALLEL=4      # Concurrent requests
export OLLAMA_MAX_LOADED_MODELS=2 # Models in memory
export OLLAMA_FLASH_ATTENTION=1   # Enable flash attention

# Create systemd service with optimizations
sudo tee /etc/systemd/system/ollama.service << EOF
[Unit]
Description=Ollama Server
After=network.target

[Service]
Type=simple
User=ollama
Environment="OLLAMA_NUM_PARALLEL=4"
Environment="OLLAMA_MAX_LOADED_MODELS=2"
Environment="OLLAMA_FLASH_ATTENTION=1"
ExecStart=/usr/local/bin/ollama serve
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ollama
sudo systemctl start ollama
```

#### vLLM Optimization

```bash
# Production vLLM with optimizations
python -m vllm.entrypoints.openai.api_server \
  --model Qwen/Qwen2.5-7B-Instruct \
  --dtype bfloat16 \
  --max-num-seqs 32 \              # Max concurrent sequences
  --max-num-batched-tokens 8192 \  # Batch size
  --enable-prefix-caching \        # Cache common prefixes
  --gpu-memory-utilization 0.95 \
  --enforce-eager false            # Use CUDA graphs
```

### 11.9 Multi-GPU Setup

#### 2x RTX 4090 for 70B Models

```bash
# Install NVIDIA drivers and CUDA
sudo apt install nvidia-driver-535 nvidia-cuda-toolkit

# Verify GPUs
nvidia-smi

# vLLM with tensor parallelism
python -m vllm.entrypoints.openai.api_server \
  --model Qwen/Qwen2.5-72B-Instruct \
  --tensor-parallel-size 2 \
  --dtype bfloat16 \
  --max-model-len 16384
```

### 11.10 Recommended Setups by Scale

| Customer Count | Recommended Setup | Model | Monthly Savings vs Cloud |
|----------------|-------------------|-------|-------------------------|
| **10-50** | Raspberry Pi 5 + Hailo | Qwen 3B | ₹500-1,500 |
| **50-100** | RTX 3060 12GB | Qwen 7B | ₹4,000-7,000 |
| **100-200** | RTX 4060 Ti 16GB | Qwen 14B | ₹8,000-15,000 |
| **200-500** | RTX 4090 24GB | Qwen 32B | ₹15,000-35,000 |
| **500+** | 2x RTX 4090 | Qwen 72B | ₹35,000-70,000 |

### 11.11 Hybrid: On-Prem Primary + Cloud Fallback

For maximum reliability, use local LLM as primary with Claude as fallback:

```json5
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "ollama/qwen2.5:7b",       // Local first
        "fallbacks": [
          "ollama/qwen2.5:3b",                // Smaller local model
          "anthropic/claude-sonnet-4"         // Cloud fallback
        ]
      }
    }
  }
}
```

This ensures:
- **Normal operation**: Uses free local LLM
- **High load**: Falls back to smaller model
- **Server issues**: Falls back to cloud (costs money but stays online)

---

## Summary: Quick Reference

### Deployment Options Comparison

| Deployment | Setup Cost | Monthly Cost | Quality | Privacy |
|------------|------------|--------------|---------|---------|
| **Fully Cloud** | ₹0 | ₹3,500-5,000 | ⭐⭐⭐⭐⭐ | ⭐⭐ |
| **Fully On-Prem (Pi)** | ₹15,000-18,000 | ₹200-400 | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Hybrid A** (Cloud+Cloud) | ₹8,000 | ₹2,500-3,500 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| **Hybrid B** (Cloud LLM+Local Voice) | ₹15,000 | ₹1,500-2,500 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| **Hybrid C** (Local LLM+Cloud Voice) | ₹18,000 | ₹500-1,000 | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Hybrid D** (Smart Routing) | ₹18,000 | ₹1,000-2,000 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |

### On-Prem GPU Server Options (for 100+ customers)

| Setup | Hardware Cost | Monthly Electricity | Model Size | Quality | Break-Even |
|-------|---------------|---------------------|------------|---------|------------|
| **Budget GPU** (RTX 3060) | ₹63,000 | ₹1,000 | 7B | ⭐⭐⭐⭐ | ~10 months |
| **Mid-range GPU** (RTX 4070 Ti) | ₹1,39,000 | ₹1,500 | 14B | ⭐⭐⭐⭐⭐ | ~7 months |
| **High-end GPU** (RTX 4090) | ₹2,63,000 | ₹2,000 | 32B | ⭐⭐⭐⭐⭐ | ~8 months |
| **Enterprise** (2x RTX 4090) | ₹3,50,000+ | ₹3,500 | 70B | ⭐⭐⭐⭐⭐ | ~6 months |

### Decision Matrix

| Your Situation | Recommended Option |
|----------------|-------------------|
| Just starting, < 50 customers | Fully Cloud |
| 50-100 customers, want low monthly cost | On-Prem GPU (RTX 3060) |
| 100-300 customers, budget for hardware | On-Prem GPU (RTX 4070 Ti) |
| 300+ customers, premium quality needed | On-Prem GPU (RTX 4090) |
| Need privacy, minimal budget | Fully On-Prem (Pi) |
| Need best quality, budget conscious | Hybrid B (Cloud LLM + Local Voice) |
| Privacy first, good voice quality | Hybrid C (Local LLM + Cloud Voice) |

---

## Next Steps

1. **Choose your deployment option** based on budget and requirements
2. **Set up hardware/cloud** as per the guide
3. **Configure Clawdbot** with appropriate config file
4. **Link WhatsApp** by scanning QR code
5. **Test with sample messages** before going live
6. **Onboard your first customer** (or use for your own business)

---

*Document created: January 2026*
*For Clawdbot deployment in Indian market*
