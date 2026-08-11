"""Load golden-query eval datasets from YAML."""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml
from inspect_ai.dataset import Sample

_REQUIRED_FIELDS = ("id", "question", "expected_query")


class DatasetValidationError(ValueError):
    """Raised when a dataset YAML or import-log sample set violates contracts."""


@dataclass(frozen=True)
class GoldenQueryItem:
    dataset: str
    id: str
    question: str
    expected_query: str


def default_datasets_dir() -> Path:
    return Path(__file__).resolve().parents[2] / "datasets"


def list_dataset_stems(datasets_dir: Path | None = None) -> list[str]:
    """List all dataset stems under ``datasets_dir`` (sorted)."""
    root = datasets_dir or default_datasets_dir()
    return [path.stem for path in sorted(root.glob("*.yaml"))]


def select_dataset_stems(
    requested_stems: list[str], datasets_dir: Path | None = None
) -> list[str]:
    """Validate requested stems, or discover all stems when none are requested."""
    available = list_dataset_stems(datasets_dir)
    if not available:
        raise ValueError("no dataset stems found")

    if not requested_stems:
        return available

    selected: list[str] = []
    available_set = set(available)
    for stem in requested_stems:
        if (
            not stem
            or stem in {".", ".."}
            or Path(stem).is_absolute()
            or "/" in stem
            or "\\" in stem
        ):
            raise ValueError(f"Dataset stem must be a plain filename stem: {stem!r}")
        if stem in selected:
            raise ValueError(f"Duplicate dataset stem: {stem}")
        if stem not in available_set:
            raise ValueError(f"Unknown dataset stem: {stem}")
        selected.append(stem)
    return selected


def _require_nonblank_str(
    value: Any,
    *,
    path: Path,
    index: int,
    field: str,
    item_id: str | None,
    normalize: bool = True,
) -> str:
    where = f"{path}: items[{index}]"
    if item_id is not None:
        where = f"{where} id={item_id!r}"
    if not isinstance(value, str):
        raise DatasetValidationError(
            f"{where}: field {field!r} must be a string, got {type(value).__name__}"
        )
    if not value.strip():
        raise DatasetValidationError(
            f"{where}: field {field!r} must be a non-blank string"
        )
    return value.strip() if normalize else value


def _normalize_item(
    raw_item: Any, *, path: Path, index: int, dataset_name: str
) -> GoldenQueryItem:
    if not isinstance(raw_item, dict):
        raise DatasetValidationError(
            f"{path}: items[{index}] must be a mapping, got {type(raw_item).__name__}"
        )

    missing = [field for field in _REQUIRED_FIELDS if field not in raw_item]
    if missing:
        raise DatasetValidationError(
            f"{path}: items[{index}]: missing required field(s): {', '.join(missing)}"
        )

    item_id = _require_nonblank_str(
        raw_item["id"], path=path, index=index, field="id", item_id=None
    )
    question = _require_nonblank_str(
        raw_item["question"],
        path=path,
        index=index,
        field="question",
        item_id=item_id,
    )
    expected_query = _require_nonblank_str(
        raw_item["expected_query"],
        path=path,
        index=index,
        field="expected_query",
        item_id=item_id,
        normalize=False,
    )
    return GoldenQueryItem(
        dataset=dataset_name,
        id=item_id,
        question=question,
        expected_query=expected_query,
    )


def load_golden_dataset(paths: list[Path]) -> list[GoldenQueryItem]:
    """Load and flatten one or more manually-authored eval YAML files."""
    items: list[GoldenQueryItem] = []
    seen_ids: dict[str, Path] = {}
    for path in paths:
        path = Path(path)
        raw = yaml.safe_load(path.read_text(encoding="utf-8"))
        if not isinstance(raw, dict):
            raise DatasetValidationError(
                f"{path}: document must be a mapping, got "
                f"{type(raw).__name__ if raw is not None else 'null'}"
            )
        if "items" not in raw:
            raise DatasetValidationError(f"{path}: missing required field 'items'")
        raw_items = raw["items"]
        if not isinstance(raw_items, list):
            raise DatasetValidationError(
                f"{path}: field 'items' must be a list, got {type(raw_items).__name__}"
            )

        dataset_name = path.stem
        for index, raw_item in enumerate(raw_items):
            item = _normalize_item(
                raw_item, path=path, index=index, dataset_name=dataset_name
            )
            prior = seen_ids.get(item.id)
            if prior is not None:
                raise DatasetValidationError(
                    f"{path}: items[{index}] id={item.id!r}: duplicate id "
                    f"(also in {prior})"
                )
            seen_ids[item.id] = path
            items.append(item)
    return items


def select_import_log_samples(
    samples: list[Any] | None,
    *,
    stem: str,
    expected_ids: set[str],
) -> list[Any]:
    """Return stem-matching samples whose IDs exactly match ``expected_ids``."""
    filtered = [
        sample
        for sample in (samples or [])
        if (getattr(sample, "metadata", None) or {}).get("dataset") == stem
    ]
    observed_ids = [str(sample.id) for sample in filtered]

    duplicates = sorted(
        sample_id
        for sample_id, count in Counter(observed_ids).items()
        if count > 1
    )
    if duplicates:
        raise DatasetValidationError(
            f"duplicate import-log sample IDs for {stem}: {duplicates}"
        )

    observed_set = set(observed_ids)
    missing = sorted(expected_ids - observed_set)
    unexpected = sorted(observed_set - expected_ids)
    if missing or unexpected:
        details: list[str] = []
        if missing:
            details.append(f"missing={missing}")
        if unexpected:
            details.append(f"unexpected={unexpected}")
        raise DatasetValidationError(
            f"import-log sample IDs for {stem} must exactly match expected IDs; "
            + "; ".join(details)
        )
    return filtered


def golden_items_to_samples(items: list[GoldenQueryItem]) -> list[Sample]:
    """Convert golden-query items to Inspect Samples (YAML id → sample id)."""
    return [
        Sample(
            id=item.id,
            input=f"/tars {item.question}",
            target="",
            metadata={
                "dataset": item.dataset,
                "id": item.id,
                "question": item.question,
                "expected_query": item.expected_query,
            },
        )
        for item in items
    ]
