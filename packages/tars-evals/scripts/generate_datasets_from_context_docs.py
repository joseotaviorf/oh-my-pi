#!/usr/bin/env python3
"""CLI entrypoint — prefer `make generate-datasets`."""

from tars_evals.generate_from_context import main

if __name__ == "__main__":
    raise SystemExit(main())
