# VibeVoice Skill for Raaz

## Quick Setup

```bash
# Clone VibeVoice
git clone https://github.com/microsoft/VibeVoice.git
cd VibeVoice
pip install -e .

# Download model
huggingface-cli download microsoft/VibeVoice-2.0-Sense-v2 --local-dir checkpoints/VibeVoice-2.0-Sense-v2

# Set environment
export VIBEVOICE_CHECKPOINT=/home/shkas/projects/raaz/VibeVoice/checkpoints/VibeVoice-2.0-Sense-v2

# Make scripts executable
chmod +x /home/shkas/projects/raaz/skills/vibevoice/scripts/*.sh

# Test
/home/shkas/projects/raaz/skills/vibevoice/scripts/generate.sh --text "Hello from VibeVoice!" --output /tmp/test.wav
```

## For Realtime Mode

Use the VibeVoice-Realtime checkpoint instead:
```bash
huggingface-cli download microsoft/VibeVoice-Realtime-0.5B --local-dir checkpoints/VibeVoice-Realtime-0.5B
export VIBEVOICE_CHECKPOINT=/home/shkas/projects/raaz/VibeVoice/checkpoints/VibeVoice-Realtime-0.5B
```

## Notes

- Requires GPU for reasonable performance
- Model files are several GB in size
- First generation takes longer (model loading)
- See SKILL.md for full documentation
