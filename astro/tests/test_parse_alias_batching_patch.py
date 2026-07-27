"""Sanity checks for the Airflow DatasetAlias batching patch."""

from __future__ import annotations

from pathlib import Path

REPO_ASTRO = Path(__file__).resolve().parents[1]
PATCH = REPO_ASTRO / "parse-alias-batching.patch"


def test_alias_batching_patch_exists_and_targets_expected_files():
    text = PATCH.read_text()
    assert "airflow/datasets/__init__.py" in text
    assert "airflow/serialization/serialized_objects.py" in text
    assert "prefetch_dataset_aliases" in text
    assert "dataset_alias_expand_cache" in text
    assert "QuintoAndar" in text
