#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = ["requests", "pyyaml", "acryl-datahub"]
# ///
"""CI script: generates ephemeral .datahub.yaml per entity .md using LiteLLM
and publishes it to DataHub via load_collections_context.py.

Markdown is the only versioned source of truth. Generated YAML is written to a
temporary directory (never committed).

Golden query ``stable_urn``: deterministic ``uuid5(entity_slug)`` — stable across
CI runs without a companion YAML in git.

Domain ``domain_urn``: fetched live from DataHub (``listDomains``) at CI start;
the LLM picks the best match from that catalog and the script validates before push.

Required env vars:
    OPENAI_API_KEY       — Bearer token for the internal LiteLLM proxy
    DATAHUB_GRAPHQL_URL  — Full URL to the DataHub GraphQL endpoint
    DATAHUB_TOKEN        — DataHub personal access token with editor role

Optional:
    LITELLM_MODEL        — override the default model "openai/gpt-5.3-codex"
    LITELLM_BASE_URL     — override the default proxy URL
    DATAHUB_CI_YAML_DIR  — override ephemeral YAML output directory

Usage in CI (auto-detects changed MDs via git diff):
    pip install requests acryl-datahub
    python packages/bietlejuice-compiler/scripts/ci_cd/generate_and_push_datahub_entities.py

Process every entity MD (loader resync / master full refresh):
    python .../generate_and_push_datahub_entities.py --all

Resync all entities when the loader changed in this commit, else changed MDs only:
    python .../generate_and_push_datahub_entities.py --resync-if-loader-changed

Usage locally — pass one or more MD file paths directly:
    uv run --script packages/bietlejuice-compiler/scripts/ci_cd/generate_and_push_datahub_entities.py \\
        docs/llm_context/business_entities/my_entity.md

Exit codes:
    0 — all entities processed and published successfully (or no MDs to process)
    1 — one or more entities failed
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

import requests
import yaml

_REPO_ROOT = Path(__file__).resolve().parents[4]
_DATAHUB_CTX = _REPO_ROOT / "dags/governance/datahub_business_context"
if str(_DATAHUB_CTX) not in sys.path:
    sys.path.insert(0, str(_DATAHUB_CTX))

from datahub_domain_catalog import (  # noqa: E402
    DataHubDomain,
    entity_exists,
    fetch_all_domains,
    format_domains_for_prompt,
    known_domain_urns,
)

_MD_DIR = _REPO_ROOT / "docs/llm_context/business_entities"
_REFERENCE_DIR = _REPO_ROOT / "dags/governance/datahub_business_context/reference"
_LOADER = (
    _REPO_ROOT / "dags/governance/datahub_business_context/load_collections_context.py"
)
_LOADER_REL = "dags/governance/datahub_business_context/load_collections_context.py"
_SKILL_MD = _REPO_ROOT / ".cursor/skills/md-to-datahub-yaml/SKILL.md"
_GOLD_STANDARD = _REFERENCE_DIR / "payments.datahub.yaml"
_GLOSSARY_EXAMPLE = _REFERENCE_DIR / "visits.datahub.yaml"

# Fixed namespace — deterministic golden-query URN per entity slug.
_URN_NAMESPACE = uuid.UUID("a1b2c3d4-e5f6-7890-abcd-ef1234567890")

_QUERY_URN_RE = re.compile(
    r"^urn:li:query:" r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
    re.IGNORECASE,
)
_STABLE_URN_LINE_RE = re.compile(
    r"^(\s*stable_urn:\s*)(?:urn:li:query:[^\s]+|\S+)\s*$",
    re.MULTILINE,
)

_DEFAULT_MODEL = "openai/gpt-5.3-codex"
_DEFAULT_BASE_URL = "https://litellm.apps.shared-prd.habitat.zone/v1"

_CI_YAML_DIR: Path | None = None


def md_path_to_data_product_id(md_path: Path) -> str:
    """``accounting_funnel.md`` → ``accounting-funnel``."""
    return md_path.stem.replace("_", "-")


def _ci_yaml_dir() -> Path:
    global _CI_YAML_DIR
    if _CI_YAML_DIR is None:
        override = os.environ.get("DATAHUB_CI_YAML_DIR", "").strip()
        _CI_YAML_DIR = (
            Path(override)
            if override
            else Path(tempfile.mkdtemp(prefix="datahub-ci-yaml-"))
        )
        _CI_YAML_DIR.mkdir(parents=True, exist_ok=True)
    return _CI_YAML_DIR


def _all_mds() -> list[Path]:
    return sorted(p for p in _MD_DIR.glob("*.md") if not p.name.startswith("_"))


def _git_changed_files() -> list[str]:
    """Return repo-relative paths changed in the current CI commit."""
    prev_sha = os.environ.get("CI_PREV_COMMIT_SHA", "").strip()
    curr_sha = os.environ.get("CI_COMMIT_SHA", "HEAD").strip() or "HEAD"

    if prev_sha:
        cmd = ["git", "diff", "--name-only", prev_sha, curr_sha]
    else:
        cmd = ["git", "diff", "--name-only", "HEAD~1", "HEAD"]

    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, check=True, cwd=_REPO_ROOT
        )
    except subprocess.CalledProcessError:
        result = subprocess.run(
            ["git", "show", "--name-only", "--format=", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
            cwd=_REPO_ROOT,
        )
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def _changed_mds() -> list[Path]:
    md_prefix = "docs/llm_context/business_entities/"
    return [
        _REPO_ROOT / f
        for f in _git_changed_files()
        if f.startswith(md_prefix)
        and f.endswith(".md")
        and not Path(f).name.startswith("_")
    ]


def _loader_changed_in_commit() -> bool:
    return _LOADER_REL in _git_changed_files()


def _resolve_targets(args: argparse.Namespace) -> list[Path]:
    if args.all:
        return _all_mds()
    if args.resync_if_loader_changed and _loader_changed_in_commit():
        print("Loader changed in this commit — re-syncing all entity MDs.")
        return _all_mds()
    if args.md_paths:
        resolved: list[Path] = []
        for arg in args.md_paths:
            p = Path(arg)
            if not p.is_absolute():
                p = _REPO_ROOT / p
            if not p.exists():
                print(f"ERROR: file not found: {p}", file=sys.stderr)
                sys.exit(1)
            if p.name.startswith("_"):
                print(f"SKIP: {p.name} is a template file.")
                continue
            resolved.append(p)
        return resolved
    return _changed_mds()


def _stable_urn(entity_slug: str) -> str:
    return f"urn:li:query:{uuid.uuid5(_URN_NAMESPACE, entity_slug)}"


def _enforce_stable_urn(yaml_content: str, stable_urn: str) -> str:
    if _STABLE_URN_LINE_RE.search(yaml_content):
        return _STABLE_URN_LINE_RE.sub(rf"\1{stable_urn}", yaml_content, count=1)
    return yaml_content


def _yaml_domain_urn(yaml_content: str) -> str:
    doc = yaml.safe_load(yaml_content)
    if not isinstance(doc, dict):
        return ""
    return str(doc.get("domain_urn") or "").strip()


def _validate_domain_urn(
    domain_urn: str,
    *,
    catalog_urns: frozenset[str],
    graphql_url: str,
    token: str,
) -> str | None:
    if not domain_urn.startswith("urn:li:domain:"):
        return f"domain_urn must start with urn:li:domain:, got {domain_urn!r}"

    if domain_urn in catalog_urns or entity_exists(graphql_url, token, domain_urn):
        return None

    sample = ", ".join(sorted(catalog_urns)[:8])
    suffix = "…" if len(catalog_urns) > 8 else ""
    return (
        f"domain_urn {domain_urn!r} not found in live DataHub catalog "
        f"({len(catalog_urns)} domains fetched). Examples: {sample}{suffix}"
    )


def _build_messages(
    md_path: Path,
    stable_urn: str,
    *,
    domains: list[DataHubDomain],
) -> list[dict]:
    skill_text = _SKILL_MD.read_text()
    md_text = md_path.read_text()
    gold_text = _GOLD_STANDARD.read_text() if _GOLD_STANDARD.exists() else ""
    glossary_text = _GLOSSARY_EXAMPLE.read_text() if _GLOSSARY_EXAMPLE.exists() else ""

    rel_md = md_path.relative_to(_REPO_ROOT)
    entity_slug = md_path_to_data_product_id(md_path)
    domains_block = format_domains_for_prompt(domains)

    system = (
        "You are a data engineer at QuintoAndar. "
        "Your task is to convert a business entity Markdown file into a DataHub YAML. "
        "Output ONLY the raw YAML content — no markdown fences, no commentary, "
        "no explanation. The entire response must be valid YAML that can be written "
        "directly to a file."
    )

    user = f"""Follow the instructions in the SKILL below to generate the DataHub YAML.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SKILL: md-to-datahub-yaml
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{skill_text}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
GOLD STANDARD REFERENCE (reference/payments.datahub.yaml)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{gold_text}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
GLOSSARY related_terms EXAMPLE (reference/visits.datahub.yaml)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{glossary_text}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
INPUT: {rel_md}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{md_text}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FIXED INPUTS (use these verbatim — do not change):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
- data_product_id : {entity_slug}
- stable_urn      : {stable_urn}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RULES:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
- Infer domain_urn from the entity Markdown: pick exactly ONE domain from the
  LIVE DATAHUB CATALOG below. Copy the URN verbatim — do NOT invent slugs.
  Choose the domain whose name and description best match the entity's scope.

LIVE DATAHUB DOMAIN CATALOG ({len(domains)} domains):
{domains_block}

- Use the stable_urn above verbatim. Do NOT generate a new UUID.
- In `datasets`, include only concrete `schema.table` pairs that exist as real tables.
  Never use wildcards (`*`), schema globs (`schema.*`), or placeholder patterns
  (`statement_*`, `reverse_accounts_*`). Omit patterns; expand to explicit names or skip.
- Glossary term `id` values must match existing DataHub term slugs when the term
  already exists; the loader resolves by display name as fallback.
- Output ONLY the YAML. No markdown fences, no commentary.
"""

    return [
        {"role": "system", "content": system},
        {"role": "user", "content": user},
    ]


def _extract_yaml(response_text: str) -> str:
    fenced = re.match(r"^```(?:yaml)?\n(.*?)```\s*$", response_text.strip(), re.DOTALL)
    if fenced:
        return fenced.group(1)
    return response_text.strip()


_CHAT_COMPLETIONS_PATH = "/chat/completions"
_TIMEOUT_SECONDS = 120
_LLM_MAX_ATTEMPTS = 3
_LLM_RETRYABLE_STATUS = frozenset({429, 502, 503, 504})


def _call_llm(messages: list[dict], model: str, base_url: str, api_key: str) -> str:
    payload = {"model": model, "messages": messages}
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    url = f"{base_url.rstrip('/')}{_CHAT_COMPLETIONS_PATH}"
    last_error: Exception | None = None

    for attempt in range(1, _LLM_MAX_ATTEMPTS + 1):
        try:
            response = requests.post(
                url,
                headers=headers,
                json=payload,
                timeout=_TIMEOUT_SECONDS,
            )
            response.raise_for_status()
            break
        except requests.HTTPError as err:
            last_error = err
            status = err.response.status_code if err.response is not None else None
            if status not in _LLM_RETRYABLE_STATUS or attempt >= _LLM_MAX_ATTEMPTS:
                raise
            delay_s = 2**attempt
            print(
                f"   WARN: LiteLLM HTTP {status} — retry {attempt}/{_LLM_MAX_ATTEMPTS - 1} "
                f"in {delay_s}s",
                file=sys.stderr,
            )
            time.sleep(delay_s)
        except requests.RequestException as err:
            last_error = err
            if attempt >= _LLM_MAX_ATTEMPTS:
                raise
            delay_s = 2**attempt
            print(
                f"   WARN: LiteLLM request failed — retry {attempt}/{_LLM_MAX_ATTEMPTS - 1} "
                f"in {delay_s}s ({err})",
                file=sys.stderr,
            )
            time.sleep(delay_s)
    else:
        assert last_error is not None
        raise last_error

    body = response.json()
    choices = body.get("choices") or []
    if not choices:
        raise ValueError(f"LiteLLM response contained no choices. Raw: {body}")

    content = (choices[0].get("message") or {}).get("content")
    if isinstance(content, str) and content.strip():
        return content
    if isinstance(content, list):
        text = "".join(
            p.get("text", "")
            for p in content
            if isinstance(p, dict) and p.get("type") == "text"
        ).strip()
        if text:
            return text

    raise ValueError(f"LiteLLM response contained no text content. Raw: {body}")


def _push_to_datahub(yaml_path: Path) -> int:
    proc = subprocess.run(
        ["uv", "run", "python", str(_LOADER), "--config", str(yaml_path)],
        check=False,
        cwd=_REPO_ROOT,
    )
    return proc.returncode


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate ephemeral DataHub YAML from entity Markdown and push to DataHub.",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Process every entity MD under docs/llm_context/business_entities/",
    )
    parser.add_argument(
        "--resync-if-loader-changed",
        action="store_true",
        help=(
            "When load_collections_context.py changed in this commit, process all MDs; "
            "otherwise only MDs changed in this commit."
        ),
    )
    parser.add_argument(
        "md_paths",
        nargs="*",
        help="Explicit MD paths (local testing). Overrides git diff unless --all is set.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv or sys.argv[1:])
    targets = _resolve_targets(args)
    if not targets:
        print("No entity MD files to process — skipping DataHub publication.")
        return 0

    model = os.environ.get("LITELLM_MODEL", _DEFAULT_MODEL).strip()
    base_url = os.environ.get("LITELLM_BASE_URL", _DEFAULT_BASE_URL).strip()
    api_key = os.environ.get("OPENAI_API_KEY", "").strip()
    datahub_url = os.environ.get("DATAHUB_GRAPHQL_URL", "").strip()
    datahub_token = os.environ.get("DATAHUB_TOKEN", "").strip()

    if not api_key:
        print("ERROR: OPENAI_API_KEY is not set.", file=sys.stderr)
        return 1
    if not datahub_url:
        print("ERROR: DATAHUB_GRAPHQL_URL is not set.", file=sys.stderr)
        return 1
    if not datahub_token:
        print("ERROR: DATAHUB_TOKEN is not set.", file=sys.stderr)
        return 1

    domains = fetch_all_domains(datahub_url, datahub_token)
    if not domains:
        print(
            "ERROR: DataHub returned zero domains — cannot infer domain_urn safely.",
            file=sys.stderr,
        )
        return 1

    catalog_urns = known_domain_urns(domains)
    yaml_dir = _ci_yaml_dir()
    print(f"Model          : {model}")
    print(f"LiteLLM proxy  : {base_url}")
    print(f"DataHub target : {datahub_url}")
    print(f"Domains loaded : {len(domains)} (live catalog from DataHub)")
    print(f"YAML workspace : {yaml_dir} (ephemeral, not committed)")
    print(f"Entities found : {len(targets)}")
    print("─" * 60)

    passed: list[str] = []
    failed: list[str] = []

    for md_path in targets:
        entity_slug = md_path_to_data_product_id(md_path)
        yaml_path = yaml_dir / f"{entity_slug}.datahub.yaml"
        stable = _stable_urn(entity_slug)

        print(f"\n▶  {entity_slug}")
        print(f"   stable_urn : {stable} (uuid5)")

        try:
            messages = _build_messages(md_path, stable, domains=domains)
            raw = _call_llm(messages, model, base_url, api_key)
        except Exception as err:
            print(f"   ERROR: LLM call failed — {err}", file=sys.stderr)
            failed.append(entity_slug)
            continue

        yaml_content = _extract_yaml(raw)
        if not yaml_content.startswith("spec_version:"):
            print(
                f"   ERROR: LLM response does not look like a valid DataHub YAML "
                f"(first chars: {yaml_content[:80]!r})",
                file=sys.stderr,
            )
            failed.append(entity_slug)
            continue

        yaml_content = _enforce_stable_urn(yaml_content, stable)

        domain_err = _validate_domain_urn(
            _yaml_domain_urn(yaml_content),
            catalog_urns=catalog_urns,
            graphql_url=datahub_url,
            token=datahub_token,
        )
        if domain_err:
            print(f"   ERROR: {domain_err}", file=sys.stderr)
            failed.append(entity_slug)
            continue

        yaml_path.write_text(yaml_content + "\n")
        print(f"   ✓ YAML written ({yaml_path.stat().st_size} bytes). Publishing…")

        exit_code = _push_to_datahub(yaml_path)
        if exit_code != 0:
            print(f"   ✗ DataHub push failed (exit {exit_code})", file=sys.stderr)
            failed.append(entity_slug)
        else:
            print("   ✓ Published to DataHub.")
            passed.append(entity_slug)

    total = len(targets)
    print(f"\n{'═' * 60}")
    print(f"Results: {len(passed)} passed / {len(failed)} failed / {total} total")

    if passed:
        print("\nPublished:")
        for name in passed:
            print(f"  ✓ {name}")

    if failed:
        print("\nFailed:", file=sys.stderr)
        for name in failed:
            print(f"  ✗ {name}", file=sys.stderr)

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
