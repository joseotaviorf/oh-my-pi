"""Merge logs/per_dataset/*/summary.json into rollup.json + gate_summary.json."""
from __future__ import annotations

import sys
from pathlib import Path

from tars_evals.config import load_config
from tars_evals.dataset import select_dataset_stems
from tars_evals.gate import SampleResult, evaluate_gate
from tars_evals.summary_io import (
    SummaryParseError,
    gate_summary_dict,
    load_per_dataset_summary,
    write_json_atomic,
)

ROOT = Path(__file__).resolve().parents[1]
PER_DS = ROOT / "logs" / "per_dataset"


def main(
    argv: list[str] | None = None,
    *,
    root: Path = ROOT,
    per_dataset_dir: Path = PER_DS,
) -> int:
    requested_stems = sys.argv[1:] if argv is None else argv
    try:
        selected_stems = select_dataset_stems(
            requested_stems, root / "datasets"
        )
    except ValueError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2

    cfg = load_config(root / "config.yaml")
    results: list[SampleResult] = []
    by_stem: dict[str, dict] = {}
    for requested_stem in selected_stems:
        path = per_dataset_dir / requested_stem / "summary.json"
        if not path.is_file():
            print(f"ERROR: Missing summary for {requested_stem}: {path}", file=sys.stderr)
            return 2
        try:
            header, samples = load_per_dataset_summary(
                path, expected_stem=requested_stem
            )
        except SummaryParseError as error:
            print(
                f"ERROR: Invalid summary for {requested_stem}: {error}",
                file=sys.stderr,
            )
            return 2
        stem = requested_stem
        by_stem[stem] = {
            "passed": header["passed"],
            "total": header["total"],
            "passed_count": header["passed_count"],
            "pass_rate": header["pass_rate"],
        }
        results.extend(samples)

    gate = evaluate_gate(results, cfg.gate_pass_rate)
    rollup = {
        "datasets_completed": len(by_stem),
        "suite": {
            "passed": gate.passed,
            "total": gate.total,
            "passed_count": gate.passed_count,
            "pass_rate": gate.pass_rate,
            "reason": gate.reason,
        },
        "per_dataset": by_stem,
    }
    write_json_atomic(per_dataset_dir / "rollup.json", rollup)
    write_json_atomic(root / "gate_summary.json", gate_summary_dict(gate))
    print(
        f"rollup: {len(by_stem)} datasets, {gate.passed_count}/{gate.total} "
        f"({gate.pass_rate:.1%}) passed"
    )
    # Exit codes: 1 = a valid, successfully-parsed run whose suite gate
    # legitimately failed (this is the suite's one authoritative gate
    # decision — fail closed); 2 = structural/input error above (bad stems,
    # missing/malformed summary, duplicate stem) — mirrors check_gate.py's
    # convention so CI/alerting can tell "harness broke" apart from "SQL
    # quality regressed".
    return 0 if gate.passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
