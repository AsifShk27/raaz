---
name: print-queue
description: Print documents to Brother printer via IPP/CUPS from WhatsApp
metadata: {"openclaw":{"emoji":"🖨️","requires":{"bins":["lp","lpstat","file"]}}}
---

# print-queue

Print documents to a Brother network printer via IPP/CUPS. Supports WhatsApp document forwarding.

## ⚠️ CRITICAL: How to Print

**ALWAYS use the shell script - NEVER use Python cups module!**

```bash
# ✅ CORRECT - Use the shell script:
/home/shkas/projects/raaz/skills/print-queue/run.sh /path/to/document.pdf

# ✅ With options:
/home/shkas/projects/raaz/skills/print-queue/run.sh /path/to/document.pdf --pages 1
/home/shkas/projects/raaz/skills/print-queue/run.sh /path/to/document.pdf --copies 2 --media A4

# ❌ WRONG - Do NOT use Python:
# python -c "import cups"  # THIS WILL FAIL!
# import cups              # THIS WILL FAIL!
```

The shell script handles everything. Just pass the file path!

## Printer Setup

**Prerequisites:**
```bash
# Install CUPS (run once)
sudo apt install cups cups-client

# Add Brother printer
sudo lpadmin -p Brother -v ipp://192.168.0.104/ipp -E

# Set as default
lpoptions -d Brother

# Verify
lpstat -v
lpstat -a
```

**Printer Config:**
- Name: `DCPT520W`
- URI: `lpd://192.168.0.104/BINARY_P1`
- Model: Brother DCP-T520W

## Usage

### Command Line
```bash
# Print a PDF
./scripts/print.sh /path/to/document.pdf

# Print with options
./scripts/print.sh /path/to/document.pdf --copies 2 --media A4

# Check printer status
lpstat -p Brother
```

### WhatsApp Integration

Users can send documents (PDF, images, text) via WhatsApp. The skill:
1. Receives file path from OpenClaw
2. Validates file type (PDF, JPG, PNG, TXT)
3. Submits print job to CUPS
4. Returns job ID and status

## Script Options

| Option | Description |
|--------|-------------|
| `--copies N` | Number of copies (default: 1) |
| `--pages RANGE` | Page range: 1, 1-3, 1,3,5 (default: all pages) |
| `--media SIZE` | Paper size: A4, Letter, etc. (default: A4) |
| `--quality QUALITY` | Print quality: draft, normal, high |
| `-- duplex ON/OFF` | Double-sided printing |
| `--job-name NAME` | Custom job name |

## Examples

```bash
# Print all pages (default)
./print.sh document.pdf

# Print only page 1
./print.sh document.pdf --pages 1

# Print pages 1-3
./print.sh document.pdf --pages 1-3

# Print pages 1, 3, and 5
./print.sh document.pdf --pages 1,3,5

# 2 copies, page 1 only
./print.sh contract.pdf --copies 2 --pages 1 --media A4

# Image print
./print.sh photo.jpg --quality high

# Check status
lpstat -W completed
lpstat -W not-completed
```

## Troubleshooting

**Printer not found:**
```bash
lpstat -v
lpinfo -v | grep ipp
```

**Print job stuck:**
```bash
# Cancel all jobs
cancel -a Brother

# Restart printer
cupsdisable Brother
cupsenable Brother
```

**Check printer status:**
```bash
lpstat -p Brother -W all
```

## Notes

- Supports: PDF, JPG, PNG, TIFF, TXT
- Default paper: A4
- Max file size: 50MB (CUPS limitation)
- Jobs appear in web UI: http://localhost:631/jobs
