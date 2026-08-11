"""Strict YAML dataset contracts for load_golden_dataset."""
from __future__ import annotations

from pathlib import Path

import pytest
from tars_evals.dataset import (
    DatasetValidationError,
    default_datasets_dir,
    load_golden_dataset,
)


def _write(path: Path, text: str) -> Path:
    path.write_text(text, encoding="utf-8")
    return path


def test_loads_valid_hand_authored_yaml_without_source_header(tmp_path: Path):
    path = _write(
        tmp_path / "accounting.yaml",
        "items:\n"
        "- id: straw-compliance\n"
        "  question: What is straw compliance?\n"
        "  expected_query: SELECT 1\n",
    )

    items = load_golden_dataset([path])

    assert len(items) == 1
    assert items[0].dataset == "accounting"
    assert items[0].id == "straw-compliance"
    assert items[0].question == "What is straw compliance?"
    assert items[0].expected_query == "SELECT 1"


def test_loads_valid_generated_yaml_with_source_header(tmp_path: Path):
    path = _write(
        tmp_path / "turnover.yaml",
        "# auto-generated\n"
        "# source: docs/llm_context/metric_entities/turnover.md\n"
        "# Do not edit — regenerate with: make generate-datasets\n"
        "items:\n"
        "- id: turnover-monthly\n"
        "  question: Monthly\n"
        "  expected_query: |\n"
        "    SELECT 2\n",
    )

    items = load_golden_dataset([path])

    assert len(items) == 1
    assert items[0].id == "turnover-monthly"
    assert items[0].question == "Monthly"
    assert items[0].expected_query.strip() == "SELECT 2"


def test_empty_items_list_returns_empty(tmp_path: Path):
    path = _write(tmp_path / "empty.yaml", "items: []\n")

    assert load_golden_dataset([path]) == []


@pytest.mark.parametrize(
    "body",
    [
        "[]\n",
        "null\n",
        "42\n",
        "just a string\n",
    ],
)
def test_rejects_non_mapping_document(tmp_path: Path, body: str):
    path = _write(tmp_path / "bad.yaml", body)

    with pytest.raises(DatasetValidationError, match=str(path)) as exc:
        load_golden_dataset([path])
    assert "document" in str(exc.value).lower() or "mapping" in str(exc.value).lower()


def test_rejects_missing_items(tmp_path: Path):
    path = _write(tmp_path / "bad.yaml", "other: true\n")

    with pytest.raises(DatasetValidationError, match=r"items") as exc:
        load_golden_dataset([path])
    assert str(path) in str(exc.value)


@pytest.mark.parametrize("items_value", ["null", "{}", "42", '"nope"'])
def test_rejects_non_list_items(tmp_path: Path, items_value: str):
    path = _write(tmp_path / "bad.yaml", f"items: {items_value}\n")

    with pytest.raises(DatasetValidationError, match=r"items") as exc:
        load_golden_dataset([path])
    assert str(path) in str(exc.value)


def test_rejects_non_mapping_item(tmp_path: Path):
    path = _write(tmp_path / "bad.yaml", "items:\n- not-a-mapping\n")

    with pytest.raises(DatasetValidationError) as exc:
        load_golden_dataset([path])
    msg = str(exc.value)
    assert str(path) in msg
    assert "0" in msg or "index" in msg.lower()


@pytest.mark.parametrize("field", ["id", "question", "expected_query"])
def test_rejects_missing_required_field(tmp_path: Path, field: str):
    fields = {
        "id": "sample-1",
        "question": "Q?",
        "expected_query": "SELECT 1",
    }
    del fields[field]
    lines = ["items:", "-"]
    for key, value in fields.items():
        lines.append(f"  {key}: {value}")
    path = _write(tmp_path / "bad.yaml", "\n".join(lines) + "\n")

    with pytest.raises(DatasetValidationError, match=field) as exc:
        load_golden_dataset([path])
    assert str(path) in str(exc.value)


@pytest.mark.parametrize("field", ["id", "question", "expected_query"])
@pytest.mark.parametrize("bad_value", ["42", "true", "null", '""', '"   "'])
def test_rejects_non_string_or_blank_required_fields(
    tmp_path: Path, field: str, bad_value: str
):
    fields = {
        "id": "sample-1",
        "question": "Q?",
        "expected_query": "SELECT 1",
    }
    fields[field] = None  # placeholder; rewritten below
    lines = ["items:", "-"]
    for key, value in fields.items():
        if key == field:
            lines.append(f"  {key}: {bad_value}")
        else:
            lines.append(f"  {key}: {value}")
    path = _write(tmp_path / "bad.yaml", "\n".join(lines) + "\n")

    with pytest.raises(DatasetValidationError, match=field) as exc:
        load_golden_dataset([path])
    assert str(path) in str(exc.value)


def test_rejects_duplicate_ids_within_one_file(tmp_path: Path):
    path = _write(
        tmp_path / "dup.yaml",
        "items:\n"
        "- id: same\n"
        "  question: First\n"
        "  expected_query: SELECT 1\n"
        "- id: same\n"
        "  question: Second\n"
        "  expected_query: SELECT 2\n",
    )

    with pytest.raises(DatasetValidationError, match=r"same") as exc:
        load_golden_dataset([path])
    msg = str(exc.value).lower()
    assert "duplicate" in msg
    assert str(path) in str(exc.value)


def test_rejects_duplicate_ids_across_loaded_files(tmp_path: Path):
    a = _write(
        tmp_path / "a.yaml",
        "items:\n"
        "- id: shared\n"
        "  question: From A\n"
        "  expected_query: SELECT 1\n",
    )
    b = _write(
        tmp_path / "b.yaml",
        "items:\n"
        "- id: shared\n"
        "  question: From B\n"
        "  expected_query: SELECT 2\n",
    )

    with pytest.raises(DatasetValidationError, match=r"shared") as exc:
        load_golden_dataset([a, b])
    msg = str(exc.value).lower()
    assert "duplicate" in msg
    assert str(a) in str(exc.value) or str(b) in str(exc.value)


def test_current_inventory_loads_via_strict_loader():
    root = default_datasets_dir()
    paths = sorted(root.glob("*.yaml"))
    assert paths, f"expected datasets under {root}"

    items = load_golden_dataset(paths)

    assert all(item.id and item.question and item.expected_query for item in items)
    assert len({item.id for item in items}) == len(items)
