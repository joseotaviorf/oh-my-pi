#!/usr/bin/env python3
"""
Apply cluster-validation argparse + write-target patches to custom Spark job scripts.

Usage:
  python patch_validation_spark_args.py dags/fintech/cyber/spark_jobs/load_cyber_raw.py
  python patch_validation_spark_args.py --from-inventory --ref origin/DPLT-1288/cluster-validation-fintech --line fintech
  python patch_validation_spark_args.py --from-inventory --ref origin/DPLT-1288/cluster-validation-fintech --line fintech --dry-run
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import List, Optional, Tuple

REPO_ROOT = Path(
    os.environ.get("BI_ETL_REPO_ROOT", Path(__file__).resolve().parents[4])
)
VALIDATION_IMPORT = """from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)"""

RESOLVE_BLOCK_LINES = [
    "write_database_name, write_table_name, write_location = resolve_datalake_write_target(",
    "    prod_database={database_name},",
    "    prod_table={table_name},",
    "    prod_location={database_location},",
    "    bucket={bucket},",
    "    target_database={target_db},",
    "    target_table={target_table},",
    ")",
]


def _format_resolve_block(indent: str, **kwargs: str) -> str:
    lines = [line.format(**kwargs) for line in RESOLVE_BLOCK_LINES]
    return "\n".join(f"{indent}{line}" for line in lines) + "\n"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _write(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")


def _already_patched(content: str) -> bool:
    if "BaseCoreModelSparkJob" in content or re.search(r"Core\w+BaseSparkJob", content):
        return True
    return "resolve_datalake_write_target(" in content


def _module_level_prefix(content: str) -> str:
    match = re.search(r"^(def |class |if __name__)", content, re.MULTILINE)
    return content[: match.start()] if match else content


def _insert_imports(content: str) -> str:
    if "from bietlejuice.base.validation.spark_args import" in content:
        return content
    prefix = _module_level_prefix(content)
    suffix = content[len(prefix) :]
    anchor_patterns = [
        r"(from bietlejuice\.base\.db import[^\n]+\n)",
        r"(from bietlejuice\.pipeline[^\n]+\n)",
        r"(from bietlejuice\.clients[^\n]+\n)",
        r"(from quintoandar_logger import[^\n]+\n)",
    ]
    for pattern in anchor_patterns:
        match = re.search(pattern, prefix)
        if match:
            insert_at = match.end()
            new_prefix = (
                prefix[:insert_at] + VALIDATION_IMPORT + "\n" + prefix[insert_at:]
            )
            return new_prefix + suffix
    first_def = re.search(r"^(def |class )", prefix, re.MULTILINE)
    if first_def:
        insert_at = first_def.start()
        head = prefix[:insert_at].rstrip("\n")
        tail = prefix[insert_at:].lstrip("\n")
        return head + "\n\n" + VALIDATION_IMPORT + "\n\n" + tail + suffix
    lines = prefix.splitlines(keepends=True)
    lines.append(VALIDATION_IMPORT + "\n")
    return "".join(lines) + suffix


def _add_parser_flags(content: str) -> str:
    if "add_validation_target_args(parser)" in content:
        return content
    if "add_validation_target_args(arg_parser)" in content:
        return content

    patterns = [
        (
            r"(\n    args = parser\.parse_args\(\))",
            "\n    add_validation_target_args(parser)\n    args = parser.parse_args()",
        ),
        (
            r"(\n    args = arg_parser\.parse_args\(\))",
            "\n    add_validation_target_args(arg_parser)\n    args = arg_parser.parse_args()",
        ),
        (
            r"(\n        return parser\n)",
            "\n        add_validation_target_args(parser)\n        return parser\n",
        ),
        (
            r"(\n    return parser\n)",
            "\n    add_validation_target_args(parser)\n    return parser\n",
        ),
    ]
    for pattern, replacement in patterns:
        if re.search(pattern, content):
            return re.sub(pattern, replacement, content, count=1)

    return content


def _detect_table_and_bucket(content: str, after_pos: int) -> Tuple[str, str]:
    tail = content[after_pos:]
    table = "table_name"
    if re.search(r"\braw_table_name\b", tail):
        table = "raw_table_name"
    bucket = "datalake_bucket"
    if re.search(r"(?<![.\w])datalake_bucket(?![.\w])", content[: after_pos + 500]):
        bucket = "datalake_bucket"
    elif re.search(r"\bargs\.datalake_bucket\b", content):
        bucket = "args.datalake_bucket"
    elif re.search(r"\bargs\.bucket\b", content):
        bucket = "args.bucket"
    return table, bucket


def _target_db_expr(content: str, func_start: int, func_end: int) -> Tuple[str, str]:
    func_body = content[func_start:func_end]
    header_end = (
        func_body.find("):") + 2 if "):" in func_body else func_body.find("):\n") + 3
    )
    header = func_body[:header_end] if header_end > 2 else func_body[:500]
    if "target_database_name" in header:
        return "target_database_name", "target_table_name"
    prefix = content[:func_start]
    if re.search(r"args\s*=\s*(?:parser\.parse_args|parse_arguments)\(", prefix):
        return "args.target_database_name", "args.target_table_name"
    if re.search(r"\bargs\.", func_body):
        return "args.target_database_name", "args.target_table_name"
    return "None", "None"


def _patch_get_db_info_block(content: str) -> str:
    pattern = re.compile(
        r"(?P<indent>[ \t]*)database_name = db_info\[\"db_raw_databricks\"\]\n"
        r"(?P=indent)(?:format_options = [^\n]+\n)?"
        r"(?P=indent)database_location = db_info\[\"db_raw_path\"\]\n",
        re.MULTILINE,
    )
    match = pattern.search(content)
    if not match:
        pattern2 = re.compile(
            r"(?P<indent>[ \t]*)database_name = db_info\[\"db_raw_databricks\"\]\n"
            r"(?P=indent)database_location = db_info\[\"db_raw_path\"\]\n",
            re.MULTILINE,
        )
        match = pattern2.search(content)
    if not match:
        pattern3 = re.compile(
            r"(?P<indent>[ \t]*)database_name = datalake_info\[\"db_raw_databricks\"\]\n"
            r"(?P=indent)(?:spark_metastore_service\.create_database\(database_name\)\n)?"
            r"(?P=indent)database_location = datalake_info\[\"db_raw_path\"\]\n",
            re.MULTILINE,
        )
        match = pattern3.search(content)
    if not match:
        return content

    if "resolve_datalake_write_target" in content[match.start() : match.end() + 400]:
        return content

    indent = match.group("indent")
    insert_pos = match.end()
    table, bucket = _detect_table_and_bucket(content, insert_pos)
    func_start = content.rfind("\ndef ", 0, match.start())
    if func_start == -1:
        func_start = 0
    func_end = content.find("\ndef ", match.start() + 1)
    if func_end == -1:
        func_end = len(content)
    target_db, target_table = _target_db_expr(content, func_start, func_end)
    if target_db == "None":
        return content

    indented = _format_resolve_block(
        indent,
        database_name="database_name",
        table_name=table,
        database_location="database_location",
        bucket=bucket,
        target_db=target_db,
        target_table=target_table,
    )

    new_content = content[:insert_pos] + indented + content[insert_pos:]
    after_resolve = insert_pos + len(indented)

    tail = new_content[after_resolve:]
    end_markers = [
        "\n\nif __name__",
        "\n\ndef ",
        "\n\nclass ",
    ]
    tail_end = len(tail)
    for marker in end_markers:
        idx = tail.find(marker)
        if idx != -1:
            tail_end = min(tail_end, idx)

    tail_segment = tail[:tail_end]
    patched_tail = tail_segment
    patched_tail = re.sub(
        r"create_database\(database_name\)",
        "create_database(write_database_name)",
        patched_tail,
    )
    patched_tail = re.sub(
        r"create_database\(write_database_name=write_database_name\)",
        "create_database(write_database_name)",
        patched_tail,
    )
    patched_tail = re.sub(
        r"update_metastore\(\s*([^,]+),\s*database_name,",
        r"update_metastore(\1, write_database_name,",
        patched_tail,
    )
    patched_tail = re.sub(
        r"update_metastore\(\s*([^,]+),\s*write_database_name,\s*([^,]+),\s*([^,]+),\s*database_location",
        r"update_metastore(\1, write_database_name, write_table_name, \3, write_location",
        patched_tail,
    )
    patched_tail = re.sub(
        r"database_name=write_database_name,\s*table_name=write_table_name,\s*database_location=write_location",
        "database_name=write_database_name, table_name=write_table_name, database_location=write_location",
        patched_tail,
    )
    patched_tail = re.sub(
        r's3_path=f"\{database_location\}',
        r's3_path=f"{write_location}',
        patched_tail,
    )
    patched_tail = re.sub(
        r's3_path=f"\{write_location\}\{table_name\}"',
        r's3_path=f"{write_location}{write_table_name}"',
        patched_tail,
    )
    patched_tail = re.sub(
        r"create_new_partitions_from_df\(\s*database_name=database_name",
        "create_new_partitions_from_df(database_name=write_database_name",
        patched_tail,
    )
    patched_tail = re.sub(
        r",\s*database_name,\s*table_name,",
        ", write_database_name, write_table_name,",
        patched_tail,
    )
    patched_tail = re.sub(
        r",\s*table_name,\s*format_options,\s*database_location",
        ", write_table_name, format_options, write_location",
        patched_tail,
    )

    return new_content[:after_resolve] + patched_tail + tail[tail_end:]


def _patch_pipeline_writes(content: str) -> str:
    """Patch FullTableLoaderPipeline / IncrementalTableLoaderPipeline kwargs."""
    if "resolve_datalake_write_target" in content:
        return content
    if (
        "FullTableLoaderPipeline" not in content
        and "IncrementalTableLoaderPipeline" not in content
    ):
        return content
    content = _patch_get_db_info_block(content)
    if "write_database_name" not in content:
        return content
    content = re.sub(
        r"database_name=write_database_name,\n\s+table_name=write_table_name,\n\s+database_location=write_location,",
        "database_name=write_database_name,\n                table_name=write_table_name,\n                database_location=write_location,",
        content,
    )
    content = re.sub(
        r"database_name=database_name,",
        "database_name=write_database_name,",
        content,
    )
    content = re.sub(
        r"table_name=table_name,",
        "table_name=write_table_name,",
        content,
    )
    content = re.sub(
        r"database_location=database_location,",
        "database_location=write_location,",
        content,
    )
    return content


def _patch_function_signature(content: str, func_name: str) -> str:
    pattern = rf"(def {re.escape(func_name)}\()\s*([^)]*)\s*(\)\s*:)"
    match = re.search(pattern, content)
    if not match or "target_database_name" in match.group(2):
        return content
    params = match.group(2).strip()
    extra = "target_database_name: str = None, target_table_name: str = None"
    if "**" in params:
        new_inner = re.sub(
            r"(\*\*\w+)",
            f"{extra},\n    \\1",
            params,
            count=1,
        )
    elif not params:
        new_inner = extra
    elif params.endswith(","):
        new_inner = f"{params}\n    {extra}"
    else:
        new_inner = f"{params}, {extra}"
    return (
        content[: match.start()]
        + f"def {func_name}({new_inner}):"
        + content[match.end() :]
    )


def _patch_helper_functions_with_db_info(content: str) -> str:
    for match in list(re.finditer(r"^def (\w+)\(", content, re.MULTILINE)):
        name = match.group(1)
        if name in ("main", "save_to_datalake"):
            continue
        func_start = match.start()
        func_end = content.find("\ndef ", func_start + 4)
        if func_end == -1:
            func_end = len(content)
        body = content[func_start:func_end]
        if (
            "DatalakeMetastoreService.get_db_info" in body
            and "resolve_datalake_write_target(" not in body
        ):
            content = _patch_function_signature(content, name)
    return content


def _patch_save_to_datalake_function(content: str) -> str:
    if "def save_to_datalake" not in content:
        return content
    content = _patch_function_signature(content, "save_to_datalake")
    if "resolve_datalake_write_target" in content:
        return content

    block = _format_resolve_block(
        "    ",
        database_name="database_name",
        table_name="table_name",
        database_location="database_location",
        bucket="datalake_bucket",
        target_db="target_database_name",
        target_table="target_table_name",
    )

    content = re.sub(
        r"(    database_location = db_info\[\"db_raw_path\"\]\n)",
        r"\1" + block,
        content,
        count=1,
    )

    save_start = content.find("def save_to_datalake")
    save_end = content.find("\ndef ", save_start + 1)
    if save_end == -1:
        save_end = content.find("\nif __name__", save_start + 1)
    segment = content[save_start:save_end]
    segment = re.sub(
        r"create_database\(database_name\)",
        "create_database(write_database_name)",
        segment,
    )
    segment = re.sub(
        r's3_path=f"\{database_location\}',
        r's3_path=f"{write_location}',
        segment,
    )
    segment = re.sub(
        r'f"\{write_location\}\{table_name\}"',
        'f"{write_location}{write_table_name}"',
        segment,
    )
    return content[:save_start] + segment + content[save_end:]


def _patch_main_function_targets(content: str) -> str:
    """Pass validation targets into main() for scripts that delegate to main()."""
    if "def main(" not in content or 'if __name__ == "__main__"' not in content:
        return content

    # main() with no parameters uses parse_arguments() internally — do not rewrite signature.
    if re.search(r"def main\(\)\s*:", content):
        return content

    content = _patch_function_signature(content, "main")
    if "def save_to_datalake(" in content:
        content = _patch_save_to_datalake_function(content)

    if "add_validation_target_args(parser)" not in content:
        content = re.sub(
            r"(\n    args = parser\.parse_args\(\))",
            "\n    add_validation_target_args(parser)\n    args = parser.parse_args()",
            content,
            count=1,
        )

    if "target_database_name=args.target_database_name" not in content:
        content = re.sub(
            r"(main\(\s*\n(?:.*\n)*?\s*table_name=args\.table_name,\s*\n)(\s*\))",
            r"\1        target_database_name=args.target_database_name,\n        target_table_name=args.target_table_name,\n\2",
            content,
            count=1,
        )

    return content


def patch_file(path: Path, *, dry_run: bool = False) -> bool:
    content = _read(path)
    if _already_patched(content):
        return False

    original = content
    content = _insert_imports(content)
    content = _add_parser_flags(content)
    content = _patch_save_to_datalake_function(content)
    content = _patch_helper_functions_with_db_info(content)
    content = _patch_get_db_info_block(content)
    content = _patch_pipeline_writes(content)
    content = _patch_main_function_targets(content)

    if content == original:
        return False

    if not dry_run:
        _write(path, content)
        repair_script = Path(__file__).parent / "repair_validation_spark_patches.py"
        if repair_script.exists():
            subprocess.run(
                [sys.executable, str(repair_script), str(path)],
                cwd=REPO_ROOT,
                env={**os.environ, "BI_ETL_REPO_ROOT": str(REPO_ROOT)},
                check=False,
            )
    return True


def _paths_incomplete(line: str) -> List[Path]:
    dag_root = REPO_ROOT / "dags" / line
    paths: List[Path] = []
    if not dag_root.exists():
        return paths
    for path in dag_root.rglob("spark_jobs/*.py"):
        if path.name.startswith("test_"):
            continue
        text = path.read_text(encoding="utf-8")
        if (
            "add_validation_target_args" in text
            and "resolve_datalake_write_target(" not in text
        ):
            paths.append(path)
    if line == "cross":
        for rel in (
            "dags/cross/base/spark_jobs/load_growth_intel_crawler_raw.py",
            "dags/cross/kong/spark_jobs/load_kong_raw.py",
            "dags/cross/request_logging/spark_jobs/fetch_data.py",
        ):
            path = REPO_ROOT / rel
            if path.exists():
                text = path.read_text(encoding="utf-8")
                if (
                    "add_validation_target_args" in text
                    and "resolve_datalake_write_target(" not in text
                ):
                    paths.append(path)
    return paths


def _paths_from_inventory(ref: str, line: str) -> List[Path]:
    script = (
        REPO_ROOT
        / "packages/bietlejuice-compiler/scripts/validation/list_validation_spark_jobs.py"
    )
    cmd = [
        sys.executable,
        str(script),
        "--ref",
        ref,
        "--line",
        line,
        "--status",
        "needs_fix",
        "--tsv",
    ]
    result = subprocess.run(
        cmd, cwd=REPO_ROOT, capture_output=True, text=True, check=True
    )
    paths: List[Path] = []
    seen = set()
    for row in result.stdout.strip().splitlines()[1:]:
        cols = row.split("\t")
        if len(cols) < 6:
            continue
        rel = cols[5]
        if not rel or rel in seen:
            continue
        seen.add(rel)
        paths.append(REPO_ROOT / rel)
    return paths


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", help="Spark job .py files to patch")
    parser.add_argument("--from-inventory", action="store_true")
    parser.add_argument("--ref", help="Git ref for inventory")
    parser.add_argument("--line", help="dags line filter")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--incomplete",
        action="store_true",
        help="Patch jobs that have validation flags but no resolve_datalake_write_target()",
    )
    args = parser.parse_args(argv)

    targets: List[Path] = [REPO_ROOT / p for p in args.paths]
    if args.incomplete:
        if not args.line:
            parser.error("--incomplete requires --line")
            return 2
        targets = _paths_incomplete(args.line)
    elif args.from_inventory:
        if not args.ref or not args.line:
            parser.error("--from-inventory requires --ref and --line")
            return 2
        targets = _paths_from_inventory(args.ref, args.line)

    patched = 0
    for path in targets:
        if not path.exists():
            print(f"SKIP missing: {path}", file=sys.stderr)
            continue
        if patch_file(path, dry_run=args.dry_run):
            patched += 1
            print(f"PATCHED: {path.relative_to(REPO_ROOT)}")
        else:
            print(f"UNCHANGED: {path.relative_to(REPO_ROOT)}", file=sys.stderr)

    print(f"Patched {patched} file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
