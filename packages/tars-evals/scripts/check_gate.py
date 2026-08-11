#!/usr/bin/env python3
"""Fail closed on a tars-evals gate summary.

Reads a gate-summary-shaped JSON file — either the suite-level
gate_summary.json written by build_rollup.py, or a per-dataset
logs/per_dataset/<stem>/summary.json — and exits non-zero when the gate did
not pass. Both shapes share the same header keys (passed, total,
passed_count, pass_rate) plus a samples list, so this works on either
without extra flags.

Exists because run_single_dataset_eval.py and build_rollup.py intentionally
always return 0 on a *successfully completed* run whose own execution didn't
error (their exit code reflects execution status; build_rollup.py additionally
fails closed on the suite gate itself, but this script gives CI or local
tooling an explicit, separately-testable way to re-check an already-written
gate summary without depending on shell pipefail semantics across a script
boundary, or without re-running anything).

Usage:
    uv run python scripts/check_gate.py gate_summary.json
    uv run python scripts/check_gate.py logs/per_dataset/turnover/summary.json

Exit codes: 0 = gate passed; 1 = gate failed; 2 = the file is missing,
unreadable, or not a valid gate summary.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from tars_evals.summary_io import load_json_object, missing_keys

_REQUIRED_KEYS = ("passed", "total", "passed_count", "pass_rate")


class GateSummaryError(ValueError):
    """The target file is missing, malformed, or not gate-summary shaped."""


def load_gate_summary(path: Path) -> dict:
    data = load_json_object(path, error_cls=GateSummaryError)
    absent = missing_keys(data, _REQUIRED_KEYS)
    if absent:
        raise GateSummaryError(
            f"{path}: missing required field(s): {', '.join(absent)}"
        )
    if not isinstance(data["passed"], bool):
        raise GateSummaryError(f"{path}: field 'passed' must be a boolean")
    return data


def render_failure_report(data: dict) -> str:
    reason = data.get("reason") or "pass-rate below threshold"
    lines = [
        f"GATE FAILED: {data['passed_count']}/{data['total']} passed "
        f"({data['pass_rate']:.1%}) \u2014 {reason}"
    ]
    failing = [s for s in data.get("samples") or [] if s.get("status") != "PASS"]
    if failing:
        lines.append("")
        lines.append("Failing samples:")
        for sample in failing:
            score = sample.get("judge_score")
            score_label = (
                f"{score}/5" if score is not None else sample.get("status", "?")
            )
            lines.append(
                f"- {sample.get('dataset', '?')} / {sample.get('id', '?')} "
                f"({score_label})"
            )
            reasoning = sample.get("reasoning")
            if reasoning:
                lines.append(f"    {reasoning}")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "summary",
        type=Path,
        help="Path to a gate_summary.json (suite) or per-dataset summary.json",
    )
    args = parser.parse_args(argv)

    try:
        data = load_gate_summary(args.summary)
    except GateSummaryError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2

    if not data["passed"]:
        print(render_failure_report(data), file=sys.stderr)
        return 1

    print(
        f"GATE PASSED: {data['passed_count']}/{data['total']} passed "
        f"({data['pass_rate']:.1%})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
