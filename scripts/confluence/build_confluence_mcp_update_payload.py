#!/usr/bin/env python3
"""Build a JSON object for the Atlassian MCP tool ``updateConfluencePage``.

The output is a single JSON object on one line (or pretty-printed with ``--pretty``)
containing ``cloudId``, ``pageId``, ``body``, ``contentFormat``, ``status``, and
optional metadata fields expected by the MCP schema (including ``parentId`` when
``--parent-id`` is set). The agent (or operator)
passes this object as the ``arguments`` payload when calling
``updateConfluencePage`` with the Confluence/Atlassian MCP server enabled in
Cursor. By default ``status`` is ``draft`` so the page stays unpublished until
a human publishes it in Confluence after review.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def _parse_args() -> argparse.Namespace:
    """Parse CLI arguments for building the MCP update payload."""
    parser = argparse.ArgumentParser(
        description=(
            "Emit JSON arguments for ``updateConfluencePage`` (Atlassian MCP) "
            "from a local Markdown file."
        )
    )
    parser.add_argument(
        "--markdown",
        required=True,
        type=Path,
        help="Path to the Markdown file to publish as the Confluence page body.",
    )
    parser.add_argument(
        "--cloud-id",
        required=True,
        help="Cloud ID (UUID) for the Confluence site.",
    )
    parser.add_argument(
        "--page-id",
        required=True,
        help="Numeric page ID to update.",
    )
    parser.add_argument(
        "--space-id",
        required=True,
        help="Space ID for the page.",
    )
    parser.add_argument(
        "--title",
        required=True,
        help="Page title.",
    )
    parser.add_argument(
        "--version-message",
        default="Sync from repository Markdown",
        help="Confluence version message for the update.",
    )
    parser.add_argument(
        "--content-format",
        default="markdown",
        choices=("markdown", "adf"),
        help="``contentFormat`` for the MCP tool (default: markdown).",
    )
    parser.add_argument(
        "--status",
        default="draft",
        choices=("draft", "current"),
        help=(
            "Confluence page status: ``draft`` (unpublished; default) or "
            "``current`` (published). Prefer ``draft`` so reviewers publish "
            "manually after approval."
        ),
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=None,
        help="Write JSON to this path instead of stdout.",
    )
    parser.add_argument(
        "--pretty",
        action="store_true",
        help="Pretty-print JSON (multi-line).",
    )
    parser.add_argument(
        "--parent-id",
        default=None,
        help=(
            "Optional parent page ID for ``updateConfluencePage`` (e.g. People Data Catalog). "
            "Omit when only the body should change."
        ),
    )
    parser.add_argument(
        "--strip-leading-h1",
        action="store_true",
        help=(
            "Remove the first Markdown line if it starts with ``# `` so the Confluence title "
            "is not duplicated in the body (recommended for ``docs/dw_*.md``)."
        ),
    )
    return parser.parse_args()


def main() -> int:
    """Load Markdown, build the MCP payload, and print or write JSON."""
    args = _parse_args()
    body = args.markdown.read_text(encoding="utf-8")
    if args.strip_leading_h1:
        lines = body.splitlines(keepends=True)
        if lines and lines[0].lstrip().startswith("# "):
            body = "".join(lines[1:])
    payload = {
        "cloudId": args.cloud_id,
        "pageId": args.page_id,
        "contentFormat": args.content_format,
        "status": args.status,
        "versionMessage": args.version_message,
        "title": args.title,
        "spaceId": args.space_id,
        "body": body,
    }
    if args.parent_id is not None:
        payload["parentId"] = args.parent_id
    indent = 2 if args.pretty else None
    text = json.dumps(payload, ensure_ascii=True, indent=indent)
    if args.output is not None:
        args.output.write_text(text + "\n", encoding="utf-8")
    else:
        sys.stdout.write(text + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
