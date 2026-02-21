#!/usr/bin/env bash
# Print Queue Skill Entry Point
# Usage: ./run.sh <file> [options]

cd "$(dirname "$0")"
exec ./scripts/print.sh "$@"
