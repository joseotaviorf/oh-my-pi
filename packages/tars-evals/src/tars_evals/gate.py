"""Suite gate: pass-rate decision, report rendering, and sample mapping."""

from __future__ import annotations

import re
from dataclasses import dataclass

# Above this share of ERROR samples the run stops being a quality measurement
# and becomes an infrastructure report: see evaluate_gate's `inconclusive`.
DEFAULT_MAX_ERROR_RATE = 0.1


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
    # Samples that never produced a verdict (connection failures, judge parse
    # errors, harness crashes). They still count against pass_rate, but past
    # max_error_rate they invalidate the verdict entirely.
    error_count: int = 0
    inconclusive: bool = False


def evaluate_gate(
    results: list[SampleResult],
    pass_rate: float,
    *,
    max_error_rate: float = DEFAULT_MAX_ERROR_RATE,
) -> GateResult:
    """Decide the gate, separating "SQL got worse" from "the harness broke".

    ERROR samples count against the pass rate as before — a handful of flaky
    samples must not be free. But once they exceed ``max_error_rate`` the run
    no longer measured anything: the result is marked ``inconclusive`` so
    callers can exit 2 (harness/infra broke) instead of 1 (quality regressed).
    An outage that kills 58 of 77 samples must not be reported as a 13% SQL
    quality score.
    """
    total = len(results)
    passed_count = sum(1 for r in results if r.status == "PASS")
    error_count = sum(1 for r in results if r.status == "ERROR")
    if total == 0:
        return GateResult(
            False, 0, 0, 0.0, results, "no samples ran", 0, inconclusive=True
        )
    rate = passed_count / total
    error_rate = error_count / total
    inconclusive = error_rate > max_error_rate
    passed = rate > pass_rate and not inconclusive
    if inconclusive:
        reason = (
            f"{error_count}/{total} samples ({error_rate:.1%}) failed with harness "
            f"or infrastructure errors (> {max_error_rate:.0%}) — the run did not "
            f"measure SQL quality"
        )
    elif not passed:
        reason = f"pass-rate {rate:.1%} <= {pass_rate:.1%}"
    else:
        reason = ""
    return GateResult(
        passed, total, passed_count, rate, results, reason, error_count, inconclusive
    )


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
    verdict = "PASS" if gate.passed else ("INCONCLUSIVE" if gate.inconclusive else "FAIL")
    arrow = "->"
    lines.append(
        f"GATE: {gate.passed_count}/{gate.total} passed "
        f"({gate.pass_rate:.1%}) {'>' if gate.passed else '<='} {pass_rate:.1%}  {arrow}  {verdict}"
    )
    if gate.error_count:
        lines.append(
            f"ERRORS: {gate.error_count}/{gate.total} sample(s) never produced a "
            f"verdict{' — ' + gate.reason if gate.inconclusive else ''}"
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

# tenacity wraps the real exception in a Future whose repr is a memory address:
# "RetryError(<Future at 0x115a1d7c0 state=finished raised APIConnectionError>)".
# Keep the exception name, drop the address — it makes every error message
# unique, which defeats grouping identical failures in a gate report.
_RETRY_FUTURE_RE = re.compile(r"<Future at 0x[0-9a-f]+ state=\w+ raised (\w+)>")

# A traceback's top-level exception lines start at column 0 (source lines are
# indented), so the first match is the root cause of the whole `raise ... from`
# chain — e.g. httpcore.ConnectError under an openai APIConnectionError.
_EXCEPTION_LINE_RE = re.compile(
    r"^([A-Za-z_][\w.]*(?:Error|Exception|Timeout|Interrupt))(?::[ \t]*(.*))?$",
    re.MULTILINE,
)

_MAX_ROOT_CAUSE_CHARS = 200


def _root_cause(traceback_text: str) -> str:
    """First exception in the chained traceback, or '' when there is none."""
    match = _EXCEPTION_LINE_RE.search(traceback_text or "")
    if match is None:
        return ""
    name, detail = match.group(1), (match.group(2) or "").strip()
    root = f"{name}: {detail}" if detail else name
    if len(root) > _MAX_ROOT_CAUSE_CHARS:
        root = root[: _MAX_ROOT_CAUSE_CHARS - 1] + "…"
    return root


def describe_sample_error(error) -> str:
    """Human-readable cause for an errored sample.

    Inspect reports the outermost exception, which for a retry-exhausted model
    call is a bare ``RetryError`` — it names neither the failing host nor the
    reason. Unwrapping the Future repr and appending the traceback's root
    cause turns "RetryError(<Future at 0x115a1d7c0 …>)" into
    "RetryError(APIConnectionError) [root cause: httpcore.ConnectError]",
    which is the difference between "TARS is broken" and "the proxy was down".
    """
    message = (getattr(error, "message", None) or str(error) or "").strip()
    message = _RETRY_FUTURE_RE.sub(r"\1", message)
    root = _root_cause(getattr(error, "traceback", None) or "")
    if root and root not in message:
        message = f"{message} [root cause: {root}]" if message else root
    return message or "unknown error"


def sample_results_from_logs(logs, threshold: int) -> list[SampleResult]:
    results: list[SampleResult] = []
    for log in logs:
        for s in (getattr(log, "samples", None) or []):
            dataset = (getattr(s, "metadata", None) or {}).get("dataset", "-")
            sid = str(getattr(s, "id", "?"))
            if getattr(s, "error", None):
                results.append(
                    SampleResult(
                        dataset, sid, None, "ERROR", describe_sample_error(s.error)
                    )
                )
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
