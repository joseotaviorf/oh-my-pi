"""Suite gate: pass-rate decision, report rendering, and sample mapping."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class SampleResult:
    dataset: str
    id: str
    judge_score: int | None
    status: str  # PASS, FAIL, NO-SQL, or ERROR
    reasoning: str


@dataclass(frozen=True)
class GateResult:
    passed: bool
    total: int
    passed_count: int
    pass_rate: float
    results: list[SampleResult]
    reason: str


def evaluate_gate(results: list[SampleResult], pass_rate: float) -> GateResult:
    total = len(results)
    passed_count = sum(1 for r in results if r.status == "PASS")
    if total == 0:
        return GateResult(False, 0, 0, 0.0, results, "no samples ran")
    rate = passed_count / total
    passed = rate > pass_rate
    reason = "" if passed else f"pass-rate {rate:.1%} <= {pass_rate:.1%}"
    return GateResult(passed, total, passed_count, rate, results, reason)


def _score_cell(r: SampleResult) -> str:
    return f"{r.judge_score}/5" if r.judge_score is not None else "-"


def render_report(gate: GateResult, *, sha: str, threshold: int, pass_rate: float) -> str:
    lines: list[str] = []
    lines.append(
        f"tars-evals gate  |  ai-tools main @ {sha}  |  "
        f"epochs=1  score>={threshold}  pass>{pass_rate:.0%}"
    )
    lines.append("")
    ds_w = max([len("DATASET")] + [len(r.dataset) for r in gate.results], default=7)
    id_w = max([len("SAMPLE")] + [len(r.id) for r in gate.results], default=6)
    header = f"{'DATASET':<{ds_w}}  {'SAMPLE':<{id_w}}  SCORE  RESULT"
    lines.append(header)
    for r in gate.results:
        lines.append(
            f"{r.dataset:<{ds_w}}  {r.id:<{id_w}}  {_score_cell(r):>5}  {r.status}"
        )
    lines.append("")
    verdict = "PASS" if gate.passed else "FAIL"
    arrow = "->"
    lines.append(
        f"GATE: {gate.passed_count}/{gate.total} passed "
        f"({gate.pass_rate:.1%}) {'>' if gate.passed else '<='} {pass_rate:.1%}  {arrow}  {verdict}"
    )
    failures = [r for r in gate.results if r.status != "PASS"]
    if failures:
        lines.append("")
        lines.append("Failures:")
        for r in failures:
            tag = _score_cell(r) if r.judge_score is not None else r.status
            lines.append(f"- {r.dataset} / {r.id} ({tag})")
            lines.append(f"    {r.reasoning}")
    return "\n".join(lines)


_SCORER_NAME = "judge_query_match"


def sample_results_from_logs(logs, threshold: int) -> list[SampleResult]:
    results: list[SampleResult] = []
    for log in logs:
        for s in (getattr(log, "samples", None) or []):
            dataset = (getattr(s, "metadata", None) or {}).get("dataset", "-")
            sid = str(getattr(s, "id", "?"))
            if getattr(s, "error", None):
                msg = getattr(s.error, "message", None) or str(s.error)
                results.append(SampleResult(dataset, sid, None, "ERROR", msg))
                continue
            score = (getattr(s, "scores", None) or {}).get(_SCORER_NAME)
            if score is None:
                results.append(SampleResult(dataset, sid, None, "ERROR", "no score produced"))
                continue
            meta = getattr(score, "metadata", None) or {}
            js = meta.get("judge_score")
            reasoning = meta.get("judge_reasoning") or ""
            if js is None:
                # A missing judge_score covers two different failure modes:
                # tars never produced SQL to grade (NO-SQL), or the judge
                # model produced SQL-grading input but returned an
                # unparsable verdict (judge_parse_error, a harness ERROR,
                # not a missing-SQL sample).
                if meta.get("judge_parse_error"):
                    results.append(
                        SampleResult(dataset, sid, None, "ERROR", reasoning or "judge parse error")
                    )
                else:
                    results.append(SampleResult(dataset, sid, None, "NO-SQL", reasoning or "no SQL"))
            else:
                status = "PASS" if js >= threshold else "FAIL"
                results.append(SampleResult(dataset, sid, js, status, reasoning))
    return results
