"""Generate tars-evals datasets from metric_entities golden queries.

Runs in two scopes:

- **Full scan** (``stems=None``) — every metric doc on disk, pruning every
  orphaned auto-generated dataset.
- **Scoped** (``stems={...}``) — only the given stems are read, written, and
  considered for pruning. CI uses this mode with
  ``scripts/changed_dataset_stems.py --write-scope-stems``. A full scan aborts
  on the first pre-existing hand-authored dataset anywhere in the tree, so
  scoping keeps collision checks limited to stems the diff actually touched.

An empty scope is a valid no-op. Callers must pass ``None`` for "everything"
rather than an empty set.
"""

from __future__ import annotations

import argparse
import re
import sys
import unicodedata
from collections.abc import Callable, Iterable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

from tars_evals.dataset_quality import exclusion_reason
from tars_evals.repo_bootstrap import load_document_parser, repo_root

_QUERY_PREFIX_RE = re.compile(
    r"^(?:"
    r"Query\s+\d+\s*[—\-–:]\s*"
    r"|\d+\.\s*"
    r"|Golden\s+quer(?:y|ies)\s*[—\-–:]\s*"
    r")",
    re.IGNORECASE,
)
_BARE_GOLDEN_QUERY_RE = re.compile(r"^Golden\s+quer(?:y|ies)$", re.IGNORECASE)
_SINGULAR_GOLDEN_H2_RE = re.compile(
    r"^##\s+Golden\s+[Qq]uery:\s*(.+?)\s*$",
    re.MULTILINE,
)
_H1_TITLE_RE = re.compile(r"^#\s+(.+?)\s*$", re.MULTILINE)
_AUTO_GENERATED_HEADER = "# auto-generated"
_SKIP_NAMES = frozenset({"_TEMPLATE.md"})


def strip_query_prefix(heading: str) -> str:
    """Strip ``Query N —``, ``N.``, and ``Golden query:`` prefixes (repeat until stable)."""
    text = heading.strip()
    while True:
        updated = _QUERY_PREFIX_RE.sub("", text).strip()
        if updated == text:
            break
        text = updated
    if _BARE_GOLDEN_QUERY_RE.fullmatch(text):
        return ""
    return text


def entity_h1_title(markdown: str) -> str | None:
    match = _H1_TITLE_RE.search(markdown)
    if not match:
        return None
    title = match.group(1).strip()
    return title or None


def slugify(text: str) -> str:
    normalized = unicodedata.normalize("NFKD", text)
    ascii_text = normalized.encode("ascii", "ignore").decode("ascii")
    slug = re.sub(r"[^a-zA-Z0-9]+", "-", ascii_text.lower()).strip("-")
    return slug or "query"


def make_item_id(stem: str, title: str, used: set[str]) -> str:
    base = f"{stem}-{slugify(title)}"
    candidate = base
    n = 2
    while candidate in used:
        candidate = f"{base}-{n}"
        n += 1
    used.add(candidate)
    return candidate


def is_auto_generated(path: Path) -> bool:
    if not path.exists():
        return True
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            return line.strip() == _AUTO_GENERATED_HEADER
    return False


def singular_golden_h2_title(markdown: str) -> str | None:
    match = _SINGULAR_GOLDEN_H2_RE.search(markdown)
    return match.group(1).strip() if match else None


@dataclass(frozen=True)
class DatasetItem:
    id: str
    question: str
    expected_query: str


def build_items(
    stem: str,
    golden_queries: list,
    *,
    markdown: str,
) -> tuple[list[DatasetItem], list[str]]:
    warnings: list[str] = []
    items: list[DatasetItem] = []
    used_ids: set[str] = set()
    singular = singular_golden_h2_title(markdown)
    h1 = entity_h1_title(markdown)

    for gq in golden_queries:
        sql = (getattr(gq, "sql", None) or "").strip()
        if not sql:
            warnings.append(f"{stem}: skipped golden with empty SQL ({gq.name!r})")
            continue
        title = strip_query_prefix(gq.name)
        if not title and singular:
            title = singular
        if not title and h1:
            title = h1
        if not title:
            title = stem.replace("_", " ")
        skip_reason = exclusion_reason(question=title, expected_query=sql)
        if skip_reason:
            warnings.append(f"{stem}: excluded eval item ({skip_reason}) for {title!r}")
            continue
        base = f"{stem}-{slugify(title)}"
        item_id = make_item_id(stem, title, used_ids)
        if item_id != base:
            warnings.append(
                f"{stem}: disambiguated duplicate title {title!r} -> {item_id}"
            )
        items.append(DatasetItem(id=item_id, question=title, expected_query=sql))
    return items, warnings


def render_dataset_yaml(
    items: list[DatasetItem],
    *,
    source_relpath: str,
) -> str:
    payload = {
        "items": [
            {
                "id": item.id,
                "question": item.question,
                "expected_query": item.expected_query,
            }
            for item in items
        ]
    }
    body = yaml.safe_dump(
        payload,
        sort_keys=False,
        allow_unicode=True,
        default_flow_style=False,
        width=1000,
    )
    return (
        f"{_AUTO_GENERATED_HEADER}\n"
        f"# source: {source_relpath}\n"
        f"# Do not edit — regenerate with: make generate-datasets\n"
        f"{body}"
    )


def generate_datasets(
    *,
    llm_context_dir: Path,
    datasets_dir: Path,
    dry_run: bool = False,
    parse_markdown: Callable[..., Any],
    repo_root: Path,
    stems: Iterable[str] | None = None,
    skip_hand_authored: bool = False,
) -> int:
    """Materialize ``datasets/<stem>.yaml`` from metric docs; prune orphans.

    ``stems=None`` scans every metric doc. Passing an iterable restricts both
    generation *and* pruning to those stems, leaving every out-of-scope
    dataset untouched — see the module docstring for why CI needs that.

    ``skip_hand_authored`` downgrades an in-scope hand-authored dataset from a
    hard error to a skip. Only the CI drift check wants this: a hand-authored
    dataset is never regenerated, so it cannot drift from its source doc, and
    failing on one would permanently block any PR that edits that doc. Normal
    generation keeps the default so a human never silently clobbers curated
    expectations.
    """
    selected = None if stems is None else set(stems)
    if selected is not None:
        if not selected:
            print("scope: empty — nothing to generate or prune")
            return 0
        print(f"scope: {len(selected)} stem(s) — {', '.join(sorted(selected))}")

    planned: list[tuple[Path, str, int]] = []  # (out_path, rendered, n_items)
    written_stems: set[str] = set()
    collisions: list[str] = []

    for subdir in ("metric_entities",):
        md_dir = llm_context_dir / subdir
        if not md_dir.is_dir():
            print(f"warning: missing {md_dir}", file=sys.stderr)
            continue
        for md in sorted(md_dir.glob("*.md")):
            if md.name in _SKIP_NAMES:
                continue
            stem = md.stem
            if selected is not None and stem not in selected:
                continue
            text = md.read_text(encoding="utf-8")
            parsed = parse_markdown(text, fallback_title=stem)
            items, warnings = build_items(
                stem, list(parsed.golden_queries), markdown=text
            )
            for w in warnings:
                print(f"warning: {w}", file=sys.stderr)
            if not items:
                print(
                    f"warning: {md}: no extractable golden queries; skipping",
                    file=sys.stderr,
                )
                continue

            out = datasets_dir / f"{stem}.yaml"
            if out.exists() and not is_auto_generated(out):
                if skip_hand_authored:
                    print(f"skip: hand-authored dataset {out}")
                else:
                    collisions.append(str(out))
                continue

            rel = md.relative_to(repo_root).as_posix()
            rendered = render_dataset_yaml(items, source_relpath=rel)
            planned.append((out, rendered, len(items)))
            written_stems.add(stem)

    if collisions:
        for path in collisions:
            print(
                f"error: refusing to overwrite hand-authored dataset {path}",
                file=sys.stderr,
            )
        return 1

    if not dry_run and planned:
        datasets_dir.mkdir(parents=True, exist_ok=True)

    for out, rendered, n_items in planned:
        action = "update" if out.exists() else "create"
        if dry_run:
            print(f"dry-run: {action} {out} ({n_items} items)")
        else:
            out.write_text(rendered, encoding="utf-8")
            print(f"{action}: {out} ({n_items} items)")

    # Pruning mutates the filesystem; dry-run only previews when the dir exists.
    if datasets_dir.is_dir():
        for path in sorted(datasets_dir.glob("*.yaml")):
            if selected is not None and path.stem not in selected:
                continue
            if not is_auto_generated(path):
                continue
            if path.stem in written_stems:
                continue
            if dry_run:
                print(f"dry-run: prune {path}")
            else:
                path.unlink()
                print(f"prune: {path}")

    return 0


def parse_stems_file(text: str) -> set[str]:
    """Parse a one-stem-per-line scope file (blank lines and ``#`` comments ignored).

    Matches what ``scripts/changed_dataset_stems.py --write-scope-stems``
    emits, so CI can pipe one straight into the other.
    """
    stems: set[str] = set()
    for line in text.splitlines():
        stripped = line.split("#", 1)[0].strip()
        if stripped:
            stems.add(stripped)
    return stems


def resolve_selected_stems(
    cli_stems: list[str] | None,
    stems_file: Path | None,
) -> set[str] | None:
    """Union the ``--stem``/``--stems-file`` inputs, or ``None`` when neither is given.

    An existing but empty ``--stems-file`` resolves to an empty set (a valid
    no-op scope), never to ``None`` — CI passes the resolver's output through
    unconditionally, and reading "no stems changed" as "regenerate everything"
    would be exactly backwards.
    """
    if cli_stems is None and stems_file is None:
        return None
    selected: set[str] = set(cli_stems or ())
    if stems_file is not None:
        selected |= parse_stems_file(stems_file.read_text(encoding="utf-8"))
    return selected


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Generate tars-evals datasets from docs/llm_context/metric_entities "
            "golden queries."
        ),
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print create/update/prune actions without writing files.",
    )
    parser.add_argument(
        "--stem",
        action="append",
        default=None,
        dest="stems",
        metavar="STEM",
        help=(
            "Scope generation and pruning to this dataset stem (repeatable). "
            "Default: every metric doc on disk."
        ),
    )
    parser.add_argument(
        "--stems-file",
        type=Path,
        default=None,
        help=(
            "Scope to the stems listed in this file, one per line "
            "(e.g. changed_dataset_stems.py --write-scope-stems output)."
        ),
    )
    parser.add_argument(
        "--skip-hand-authored",
        action="store_true",
        help=(
            "Skip in-scope hand-authored datasets instead of failing on them. "
            "For the CI drift check only: a hand-authored dataset is never "
            "regenerated, so it cannot drift from its source doc."
        ),
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=None,
        help="Override the repository root (default: auto-discovered).",
    )
    parser.add_argument(
        "--datasets-dir",
        type=Path,
        default=None,
        help="Override the generated datasets directory.",
    )
    args = parser.parse_args(argv)

    try:
        selected = resolve_selected_stems(args.stems, args.stems_file)
    except OSError as error:
        print(f"ERROR: cannot read --stems-file: {error}", file=sys.stderr)
        return 2

    root = args.repo_root or repo_root()
    datasets_dir = args.datasets_dir or root / "packages" / "tars-evals" / "datasets"
    doc_parser = load_document_parser()
    return generate_datasets(
        llm_context_dir=root / "docs" / "llm_context",
        datasets_dir=datasets_dir,
        dry_run=args.dry_run,
        parse_markdown=doc_parser.parse_entity_markdown,
        repo_root=root,
        stems=selected,
        skip_hand_authored=args.skip_hand_authored,
    )
