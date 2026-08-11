#!/usr/bin/env python3
"""Upload tars-evals Inspect logs to ``s3://5a-tars-prod-data/evals/inspect/...``.

Used by ``.woodpecker/tars_evals.yml`` after ``run_dataset_queue.sh`` so gate
failures remain auditable once the Woodpecker runner is gone.

Default behaviour is best-effort: upload errors print a WARN and exit 0 so a
missing IAM grant cannot block the eval gate. Set
``TARS_EVAL_REQUIRE_S3_UPLOAD=1`` to fail closed on upload errors.
"""

from __future__ import annotations

import argparse
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_BUCKET = "5a-tars-prod-data"
DEFAULT_PREFIX_ROOT = "evals/inspect"


def build_prefix(
    *,
    now: datetime | None = None,
    pipeline_event: str = "",
    pull_request: str = "",
    commit_sha: str = "",
    pipeline_number: str = "",
    prefix_root: str = DEFAULT_PREFIX_ROOT,
) -> str:
    """Return the S3 key prefix for one CI (or local) eval run."""
    stamp = (now or datetime.now(timezone.utc)).strftime("%Y/%m/%d")
    event = (pipeline_event or "").strip().lower()
    pr = (pull_request or "").strip()
    sha = (commit_sha or "unknown").strip()[:12] or "unknown"
    if event == "pull_request" and pr:
        run_id = f"pr-{pr}"
    elif sha != "unknown":
        run_id = f"push-{sha}"
    else:
        run_id = "local"
    pipe = (pipeline_number or "local").strip() or "local"
    return f"{prefix_root.rstrip('/')}/{stamp}/{run_id}/pipeline-{pipe}"


def _iter_files(source: Path) -> list[Path]:
    if not source.is_dir():
        return []
    return sorted(path for path in source.rglob("*") if path.is_file())


def upload_directory(
    *,
    bucket: str,
    prefix: str,
    source: Path,
    extra_files: list[Path] | None = None,
    s3_client=None,
) -> list[str]:
    """Upload ``source`` recursively (plus optional extras) under ``prefix``.

    Returns the list of uploaded ``s3://`` URIs.
    """
    if s3_client is None:
        import boto3

        s3_client = boto3.client("s3")

    uploaded: list[str] = []
    for path in _iter_files(source):
        relative = path.relative_to(source).as_posix()
        key = f"{prefix.rstrip('/')}/{relative}"
        s3_client.upload_file(str(path), bucket, key)
        uploaded.append(f"s3://{bucket}/{key}")

    for path in extra_files or []:
        if not path.is_file():
            continue
        key = f"{prefix.rstrip('/')}/{path.name}"
        s3_client.upload_file(str(path), bucket, key)
        uploaded.append(f"s3://{bucket}/{key}")
    return uploaded


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        type=Path,
        default=Path("logs/per_dataset"),
        help="Directory to upload recursively (default: logs/per_dataset)",
    )
    parser.add_argument(
        "--bucket",
        default=os.environ.get("TARS_EVAL_S3_BUCKET", DEFAULT_BUCKET),
        help=f"Destination bucket (default: {DEFAULT_BUCKET})",
    )
    parser.add_argument(
        "--prefix-root",
        default=os.environ.get("TARS_EVAL_S3_PREFIX_ROOT", DEFAULT_PREFIX_ROOT),
        help=f"Key prefix root (default: {DEFAULT_PREFIX_ROOT})",
    )
    parser.add_argument(
        "--extra",
        type=Path,
        action="append",
        default=[],
        help="Additional file to place at the prefix root (repeatable)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the destination prefix and file count without uploading",
    )
    args = parser.parse_args(argv)

    require = os.environ.get("TARS_EVAL_REQUIRE_S3_UPLOAD", "").strip() in {
        "1",
        "true",
        "TRUE",
        "yes",
        "YES",
    }

    prefix = build_prefix(
        pipeline_event=os.environ.get("CI_PIPELINE_EVENT", ""),
        pull_request=os.environ.get("CI_COMMIT_PULL_REQUEST", "")
        or os.environ.get("CI_COMMIT_PULL_REQUEST_NUMBER", ""),
        commit_sha=os.environ.get("CI_COMMIT_SHA", ""),
        pipeline_number=os.environ.get("CI_PIPELINE_NUMBER", ""),
        prefix_root=args.prefix_root,
    )
    uri_root = f"s3://{args.bucket}/{prefix}"
    files = _iter_files(args.source)
    extras = [path for path in args.extra if path.is_file()]

    if not files and not extras:
        print(f"NOTE: nothing to upload under {args.source} — skipping S3 archive")
        print(f"Would-be prefix: {uri_root}")
        return 0

    print(f"Inspect archive prefix: {uri_root}")
    print(f"Files to upload: {len(files) + len(extras)}")

    if args.dry_run:
        for path in files:
            print(f"  {path.relative_to(args.source).as_posix()}")
        for path in extras:
            print(f"  {path.name}")
        return 0

    try:
        uploaded = upload_directory(
            bucket=args.bucket,
            prefix=prefix,
            source=args.source,
            extra_files=extras,
        )
    except Exception as error:  # noqa: BLE001 — surface any AWS/client failure
        print(f"WARN: failed to upload Inspect logs to {uri_root}: {error}", file=sys.stderr)
        if require:
            return 2
        print(
            "WARN: continuing without durable Inspect archive "
            "(set TARS_EVAL_REQUIRE_S3_UPLOAD=1 to fail closed)",
            file=sys.stderr,
        )
        return 0

    print(f"Uploaded {len(uploaded)} object(s)")
    print(f"INSPECT_S3_URI={uri_root}")
    print(f"Open with: aws s3 sync '{uri_root}/' ./inspect-archive/ && uv run inspect view")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
