"""Guard ``metric_schema.yml`` — its closed vocabularies, and which fields it demands.

Guard the closed vocabularies against production.

A closed vocabulary is only safe while it covers every value already committed.
``validate-metadata-files-content`` runs on *changed* files, so a value the regex
forgot does not fail on the PR that introduces the vocabulary — it fails much later,
on whoever next edits an unrelated line of that metadata file. This test closes that
gap by checking the whole corpus up front, which is exactly the manual step that let
``Conversational XP`` slip through when the vocabulary was first written.

It also guards the other direction of staleness: the corpus grows while a branch is
open. ``Conversational XP`` arrived on a DAG merged to master after this branch started,
so a census taken on the branch tip alone reports it as unused.
"""

from __future__ import annotations

import re
from pathlib import Path

import yamale
import yaml


def _repo_root() -> Path:
    """Walk up to the directory holding both ``dags/`` and ``packages/``.

    Resolved by marker rather than a fixed ``parents[n]`` index, which silently points
    at the wrong directory the moment a test file moves one level.
    """
    for candidate in Path(__file__).resolve().parents:
        if (candidate / "dags").is_dir() and (candidate / "packages").is_dir():
            return candidate
    raise AssertionError("repository root not found above this test file")


REPO_ROOT = _repo_root()
_METRIC_SCHEMA = (
    REPO_ROOT
    / "packages"
    / "bietlejuice-compiler"
    / "scripts"
    / "services"
    / "metadata_file_schemas"
    / "metric_schema.yml"
)


def _schema_vocabulary(field: str) -> re.Pattern[str]:
    """The ``regex(...)`` allowlist declared for ``field`` in the metric schema."""
    schema = _METRIC_SCHEMA.read_text()
    # ``[^)]*`` tolerates trailing validator arguments such as ``required=False``.
    match = re.search(rf"^\s*{field}: regex\('([^']+)'[^)]*\)", schema, re.MULTILINE)
    assert match, f"{field} is not declared as a closed vocabulary in metric_schema.yml"
    return re.compile(f"^(?:{match.group(1)})$")


def _committed_values(field: str) -> dict[str, list[str]]:
    """Every value of ``field`` across committed metric metadata, by originating file."""
    values: dict[str, list[str]] = {}
    for path in REPO_ROOT.glob("dags/**/metadata/metric/*.yml"):
        try:
            document = yaml.safe_load(path.read_text())
        except yaml.YAMLError:
            continue
        if not isinstance(document, dict):
            continue
        for column in (document.get("columns") or {}).values():
            metric = column.get("metric") if isinstance(column, dict) else None
            if not isinstance(metric, dict):
                continue
            value = metric.get(field)
            if value is not None:
                values.setdefault(str(value), []).append(
                    str(path.relative_to(REPO_ROOT))
                )
    return values


def test_every_committed_business_stage_matches_the_vocabulary():
    allowed = _schema_vocabulary("business_stage")
    offenders = {
        value: sorted(set(files))
        for value, files in _committed_values("business_stage").items()
        if not allowed.match(value)
    }
    assert not offenders, (
        "business_stage values already committed that the closed vocabulary rejects — "
        "editing any of these files for an unrelated reason would fail CI. Either add "
        f"the value to metric_schema.yml or correct the files: {offenders}"
    )


def test_the_corpus_is_actually_being_scanned():
    """Without this, a bad glob would make the guard above pass by finding nothing."""
    assert len(_committed_values("business_stage")) >= 5


def _metric_metadata(**metric_overrides: object) -> str:
    metric = {
        "name": "My Metric",
        "description": "What it measures.",
        "is_additive": False,
        "business_stage": "Post Contract",
        "approved_by": "someone@quintoandar.com.br",
    }
    metric.update(metric_overrides)
    metric = {key: value for key, value in metric.items() if value is not None}
    return yaml.safe_dump(
        {
            "database_name": "datalake_for_rent_metric",
            "table_name": "my_metric",
            "owner": "someone@quintoandar.com.br",
            "domain": "For Rent",
            "description": "A table.",
            "columns": {"value": {"description": "The value.", "metric": metric}},
        }
    )


def _schema_errors(document: str) -> list[str]:
    schema = yamale.make_schema(str(_METRIC_SCHEMA))
    try:
        yamale.validate(schema, yamale.make_data(content=document))
    except yamale.YamaleError as error:
        return [message for result in error.results for message in result.errors]
    return []


def test_metric_without_business_stage_validates():
    # The metric entity questionnaire stopped asking for it, so the metric layer must
    # accept documents that never carry the key.
    assert _schema_errors(_metric_metadata(business_stage=None)) == []


def test_metric_with_business_stage_still_validates():
    assert _schema_errors(_metric_metadata()) == []


def test_business_stage_outside_the_vocabulary_is_still_rejected():
    # Optional is not unchecked: a present value is held to the closed vocabulary.
    errors = _schema_errors(_metric_metadata(business_stage="Suply"))
    assert any("business_stage" in error for error in errors), errors
