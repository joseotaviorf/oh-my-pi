#!/usr/bin/env python3
"""Print dataset stems for eval-suite queue scripts (one per line)."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from tars_evals.dataset import default_datasets_dir, select_dataset_stems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--datasets-dir",
        type=Path,
        default=None,
        help="Override datasets/ directory (default: package datasets/)",
    )
    parser.add_argument(
        "stems",
        nargs="*",
        help="Optional dataset stems to validate and emit in the given order",
    )
    args = parser.parse_args(argv)

    try:
        stems = select_dataset_stems(
            args.stems, args.datasets_dir or default_datasets_dir()
        )
    except ValueError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    for stem in stems:
        print(stem)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
