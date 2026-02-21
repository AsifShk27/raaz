#!/usr/bin/python3
"""Trading Platform Deploy CLI entrypoint."""

import sys

try:
    import yaml  # noqa: F401
except ImportError:
    print("Error: PyYAML is required. Install with: pip install pyyaml")
    sys.exit(1)

from tpdeploy_lib.cli import main


if __name__ == "__main__":
    sys.exit(main())
