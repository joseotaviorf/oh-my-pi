"""Run gate scoring for one datasets/<stem>.yaml (no monolithic suite)."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from inspect_ai import eval as inspect_eval
from tars_evals.config import load_config
from tars_evals.dataset import (
    DatasetValidationError,
    golden_items_to_samples,
    load_golden_dataset,
    select_dataset_stems,
    select_import_log_samples,
)
from tars_evals.gate import (
    GateResult,
    evaluate_gate,
    render_report,
    sample_results_from_logs,
)
from tars_evals.summary_io import per_dataset_summary_dict, write_json_atomic
from tars_evals.task import _CONFIG_PATH, _PACKAGE_ROOT, make_tars_eval_task


def _write_outputs(stem: str, gate, results, config) -> Path:
    out_dir = _PACKAGE_ROOT / "logs" / "per_dataset" / stem
    out_dir.mkdir(parents=True, exist_ok=True)
    sha = os.environ.get("TARS_AITOOLS_SHA", "unknown")
    report = render_report(
        gate,
        sha=sha,
        threshold=config.judge_threshold,
        pass_rate=config.gate_pass_rate,
    )
    (out_dir / "gate_report.txt").write_text(report)
    write_json_atomic(
        out_dir / "summary.json",
        per_dataset_summary_dict(stem, gate),
    )
    return out_dir


def resolve_max_connections(sample_count: int, *, env_value: str | None = None) -> int:
    """Per-stem Inspect sample concurrency.

    Default is the selected dataset size (at least 1). When
    ``TARS_EVAL_MAX_CONNECTIONS`` is set, it caps that dynamic default for
    CI/proxy backpressure.
    """
    dynamic = max(1, sample_count)
    if env_value is None:
        env_value = os.environ.get("TARS_EVAL_MAX_CONNECTIONS")
    if env_value is None:
        return dynamic
    raw = env_value.strip()
    if not raw.isdigit() or int(raw) < 1:
        raise ValueError(
            f"TARS_EVAL_MAX_CONNECTIONS must be a positive integer (got: {env_value!r})"
        )
    return min(int(raw), dynamic)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stem", help="datasets/<stem>.yaml basename")
    parser.add_argument(
        "--import-log",
        type=Path,
        help="Reuse samples from an existing .eval log (filter by dataset metadata)",
    )
    args = parser.parse_args()
    datasets_dir = _PACKAGE_ROOT / "datasets"
    try:
        stem = select_dataset_stems([args.stem], datasets_dir)[0]
    except ValueError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2

    config = load_config(_CONFIG_PATH)
    yaml_path = datasets_dir / f"{stem}.yaml"

    try:
        items = load_golden_dataset([yaml_path])
    except DatasetValidationError as error:
        print(f"ERROR: Invalid dataset {stem}: {error}", file=sys.stderr)
        return 2
    if not items:
        # Still write summary.json: build_rollup.py requires every explicitly
        # selected stem to have one and hard-fails (exit 2) otherwise. A
        # dataset with zero golden queries (e.g. everything got excluded by
        # dataset_quality filters) contributes nothing to the aggregate
        # gate — that's a vacuous pass, distinct from evaluate_gate([])'s
        # hard-fail "no samples ran" reason, which guards the different
        # failure mode of items existing but inspect returning zero results.
        print(f"Empty dataset {stem}")
        gate = GateResult(
            passed=True,
            total=0,
            passed_count=0,
            pass_rate=1.0,
            results=[],
            reason="dataset has no golden queries",
        )
        out_dir = _write_outputs(stem, gate, [], config)
        print(f"\nWrote {out_dir}/summary.json")
        return 0

    expected_ids = {i.id for i in items}

    if args.import_log:
        from inspect_ai.log import read_eval_log

        log = read_eval_log(str(args.import_log))
        try:
            filtered = select_import_log_samples(
                log.samples or [],
                stem=stem,
                expected_ids=expected_ids,
            )
        except DatasetValidationError as error:
            print(f"ERROR: Import incomplete for {stem}: {error}", file=sys.stderr)
            return 3

        class _OneLog:
            samples = filtered

        results = sample_results_from_logs([_OneLog()], config.judge_threshold)
    else:
        samples = golden_items_to_samples(items)
        task = make_tars_eval_task(samples, config=config)
        out_dir = _PACKAGE_ROOT / "logs" / "per_dataset" / stem
        log_dir = out_dir / "inspect_logs"
        log_dir.mkdir(parents=True, exist_ok=True)
        display = os.environ.get("INSPECT_DISPLAY", "plain")
        # Default: all samples in this stem concurrently. Optional
        # TARS_EVAL_MAX_CONNECTIONS caps that for CI/proxy backpressure.
        try:
            max_conn = resolve_max_connections(len(samples))
        except ValueError as error:
            print(f"ERROR: {error}", file=sys.stderr)
            return 2
        logs = inspect_eval(
            task,
            epochs=1,
            max_connections=max_conn,
            # Explicit zeros: Inspect HTTP retries are unlimited when unset;
            # sample retries also default off but pin for CI clarity.
            max_retries=0,
            retry_on_error=0,
            fail_on_error=False,
            display=display,
            log_dir=str(log_dir),
        )
        results = sample_results_from_logs(logs, config.judge_threshold)

    gate = evaluate_gate(results, config.gate_pass_rate)
    out_dir = _write_outputs(stem, gate, results, config)
    print(
        render_report(
            gate,
            sha=os.environ.get("TARS_AITOOLS_SHA", "unknown"),
            threshold=config.judge_threshold,
            pass_rate=config.gate_pass_rate,
        )
    )
    print(f"\nWrote {out_dir}/summary.json")
    # Exit 0 here means "the run completed and wrote a summary" — it is
    # intentionally independent of gate.passed. The per-stem threshold is
    # stricter (small denominators) than the suite-wide one, so gating here
    # too would abort the whole queue before other stems run and before
    # build_rollup.py ever sees the results. build_rollup.py is the single
    # authoritative gate (see its fail-closed return); this script's exit
    # code communicates execution status only. See test_run_single_dataset_eval.py
    # for a locked-in regression test of this contract.
    return 0


if __name__ == "__main__":
    sys.exit(main())
