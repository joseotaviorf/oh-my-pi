from types import SimpleNamespace

import tars_evals.gate as gate_mod
from tars_evals.gate import (
    SampleResult,
    evaluate_gate,
    render_report,
    sample_results_from_logs,
)


def test_gate_has_no_main():
    assert getattr(gate_mod, "main", None) is None


def _r(status, score=None, ds="offboarding", id="x", reason=""):
    return SampleResult(ds, id, score, status, reason)


def test_gate_passes_strictly_above_rate():
    # 9/10 = 0.9 is NOT > 0.9 → fail; 10/10 → pass
    nine = [_r("PASS", 5, id=f"p{i}") for i in range(9)] + [_r("FAIL", 3, id="f")]
    assert evaluate_gate(nine, 0.9).passed is False
    allpass = [_r("PASS", 5, id=f"p{i}") for i in range(10)]
    assert evaluate_gate(allpass, 0.9).passed is True


def test_no_sql_and_error_count_against_denominator():
    res = [_r("PASS", 5, id="a"), _r("NO-SQL", None, id="b"), _r("ERROR", None, id="c")]
    g = evaluate_gate(res, 0.9)
    assert g.total == 3 and g.passed_count == 1 and g.passed is False


def test_empty_run_hard_fails():
    g = evaluate_gate([], 0.9)
    assert g.passed is False and "no samples" in g.reason.lower()
    # Nothing ran, so there is no quality verdict to report — that is a harness
    # failure (exit 2), not a regression (exit 1).
    assert g.inconclusive is True


def test_error_flood_is_inconclusive_not_a_quality_verdict():
    """The 2026-08-17 outage: 58/77 samples died in the TLS handshake and the
    gate reported 13% as though the SQL had regressed."""
    res = [_r("PASS", 5, id=f"p{i}") for i in range(19)] + [
        _r("ERROR", None, id=f"e{i}", reason="ConnectError") for i in range(58)
    ]

    g = evaluate_gate(res, 0.9)

    assert g.inconclusive is True
    assert g.passed is False
    assert g.error_count == 58
    assert "infrastructure errors" in g.reason
    assert "pass-rate" not in g.reason


def test_errors_within_tolerance_still_count_against_the_gate():
    """Flakiness below max_error_rate is not free — it just isn't relabelled."""
    # 2/20 errors sits exactly ON the 10% ceiling (strictly-greater), so the
    # run is still graded — and the 2 errors drag 18/20 down to 90%, which is
    # not strictly above gate_pass_rate.
    res = [_r("PASS", 5, id=f"p{i}") for i in range(18)] + [
        _r("ERROR", None, id="e1"),
        _r("ERROR", None, id="e2"),
    ]

    g = evaluate_gate(res, 0.9, max_error_rate=0.1)

    assert g.inconclusive is False
    assert g.error_count == 2
    assert g.passed is False
    assert "pass-rate" in g.reason


def test_a_clean_pass_stays_a_pass():
    res = [_r("PASS", 5, id=f"p{i}") for i in range(10)]

    g = evaluate_gate(res, 0.9)

    assert g.passed is True and g.inconclusive is False and g.error_count == 0


def test_report_labels_an_inconclusive_run_distinctly():
    res = [_r("PASS", 5, id="ok")] + [
        _r("ERROR", None, id=f"e{i}", reason="ConnectError") for i in range(4)
    ]

    txt = render_report(evaluate_gate(res, 0.9), sha="a1b2c3d", threshold=4, pass_rate=0.9)

    assert "INCONCLUSIVE" in txt
    assert "ERRORS: 4/5" in txt


def test_report_lists_failures_with_reasoning():
    res = [
        _r("PASS", 5, id="ok"),
        _r("FAIL", 3, id="bad", reason="DONE filter changes the population."),
        _r("NO-SQL", None, id="empty", reason="tars produced no SQL to grade."),
    ]
    txt = render_report(evaluate_gate(res, 0.9), sha="a1b2c3d", threshold=4, pass_rate=0.9)
    assert "a1b2c3d" in txt
    assert "GATE:" in txt and "FAIL" in txt
    assert "Failures:" in txt
    assert "DONE filter changes the population." in txt
    assert "bad" in txt and "empty" in txt
    # a passing sample is in the table but NOT in the Failures section
    failures_section = txt.split("Failures:")[1]
    assert "ok" not in failures_section


def _sample(id, dataset, score_meta=None, value=None, error=None):
    scores = None
    if score_meta is not None or value is not None:
        scores = {"judge_query_match": SimpleNamespace(
            value=value, explanation="", metadata=score_meta or {})}
    return SimpleNamespace(id=id, metadata={"dataset": dataset},
                           scores=scores, error=error)


def test_maps_samples_to_results():
    logs = [SimpleNamespace(samples=[
        _sample("a", "offboarding", {"judge_score": 5, "judge_reasoning": "ok"}, "C"),
        _sample("b", "offboarding", {"judge_score": 3, "judge_reasoning": "pop diff"}, "I"),
        _sample("c", "offboarding", {"judge_score": None, "judge_reasoning": "no sql"}, "I"),
        _sample("d", "chatbot", error=SimpleNamespace(message="boom")),
    ])]
    res = sample_results_from_logs(logs, threshold=4)
    by = {r.id: r for r in res}
    assert by["a"].status == "PASS"
    assert by["b"].status == "FAIL"
    assert by["c"].status == "NO-SQL"
    assert by["d"].status == "ERROR" and "boom" in by["d"].reasoning


_RETRY_ERROR_TRACEBACK = """Traceback (most recent call last):
  File "httpcore/_backends/anyio.py", line 67, in start_tls
    with map_exceptions(exc_map):
httpcore.ConnectError

The above exception was the direct cause of the following exception:

Traceback (most recent call last):
    response = await transport.handle_async_request(request)
httpx.ConnectError

The above exception was the direct cause of the following exception:

Traceback (most recent call last):
    result = await fn(*args, **kwargs)
tenacity.RetryError: RetryError[<Future at 0x115a1d7c0 state=finished raised APIConnectionError>]
"""


def test_error_message_names_the_real_cause_not_a_memory_address():
    """`RetryError(<Future at 0x115a1d7c0 ...>)` is what the gate report used to
    print for a proxy outage: no host, no reason, and a unique address per
    sample so identical failures never grouped."""
    logs = [SimpleNamespace(samples=[
        _sample("a", "turnover", error=SimpleNamespace(
            message="RetryError(<Future at 0x115a1d7c0 state=finished raised APIConnectionError>)",
            traceback=_RETRY_ERROR_TRACEBACK,
        )),
    ])]

    reasoning = sample_results_from_logs(logs, threshold=4)[0].reasoning

    assert "0x115a1d7c0" not in reasoning
    assert "RetryError(APIConnectionError)" in reasoning
    assert "httpcore.ConnectError" in reasoning


def test_error_message_without_a_traceback_is_left_alone():
    logs = [SimpleNamespace(samples=[
        _sample("a", "turnover", error=SimpleNamespace(message="boom", traceback=None)),
    ])]

    assert sample_results_from_logs(logs, threshold=4)[0].reasoning == "boom"


def test_unparsable_judge_response_maps_to_error_not_no_sql():
    logs = [SimpleNamespace(samples=[
        _sample(
            "e",
            "offboarding",
            {
                "judge_score": None,
                "judge_reasoning": "judge response was unparsable.",
                "judge_parse_error": True,
            },
            "I",
        ),
    ])]
    res = sample_results_from_logs(logs, threshold=4)
    by = {r.id: r for r in res}
    assert by["e"].status == "ERROR"
    assert "unparsable" in by["e"].reasoning
