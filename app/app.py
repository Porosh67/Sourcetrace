#!/usr/bin/env python3
"""Harness entry point.

    python3 /app/app.py --index /app/corpus
    python3 /app/app.py --corpus /app/corpus --query-id query_01 --query "..."

Everything lives in the ``sourcetrace`` package next to this file. This stays a thin
client: the model and the index live in the resident server started by the container CMD
(``python3 /app/app.py --serve``).
"""

import sys
import time

_STARTED_AT = time.monotonic()
sys.path.insert(0, __file__.rsplit("/", 1)[0] if "/" in __file__ else ".")

from sourcetrace.cli import main

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:], started_at=_STARTED_AT))
