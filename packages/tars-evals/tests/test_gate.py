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
