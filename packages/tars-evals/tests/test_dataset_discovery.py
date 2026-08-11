import subprocess
import sys
from pathlib import Path

import pytest
import tars_evals.dataset as dataset_module
from tars_evals.dataset import list_dataset_stems


def test_list_dataset_stems(tmp_path: Path):
    (tmp_path / "metric_a.yaml").write_text(
        "# source: docs/llm_context/metric_entities/a.md\nitems: []\n",
        encoding="utf-8",
    )
    (tmp_path / "hand.yaml").write_text("items: []\n", encoding="utf-8")

    assert list_dataset_stems(tmp_path) == ["hand", "metric_a"]


def test_select_dataset_stems_defaults_to_deterministic_discovery(tmp_path: Path):
    (tmp_path / "zeta.yaml").write_text("items: []\n")
    (tmp_path / "alpha-name.yaml").write_text("items: []\n")

    assert dataset_module.select_dataset_stems([], tmp_path) == [
        "alpha-name",
        "zeta",
    ]


@pytest.mark.parametrize(
    "stem",
    ["", ".", "..", "../alpha", "nested/alpha", r"nested\alpha", "/tmp/alpha"],
)
def test_select_dataset_stems_rejects_non_plain_stems(tmp_path: Path, stem: str):
    (tmp_path / "alpha.yaml").write_text("items: []\n")

    with pytest.raises(ValueError, match="plain filename stem"):
        dataset_module.select_dataset_stems([stem], tmp_path)


def test_select_dataset_stems_rejects_unknown_stem(tmp_path: Path):
    (tmp_path / "alpha.yaml").write_text("items: []\n")

    with pytest.raises(ValueError, match="Unknown dataset stem"):
        dataset_module.select_dataset_stems(["missing"], tmp_path)


def test_select_dataset_stems_rejects_duplicates(tmp_path: Path):
    (tmp_path / "alpha.yaml").write_text("items: []\n")

    with pytest.raises(ValueError, match="Duplicate dataset stem"):
        dataset_module.select_dataset_stems(["alpha", "alpha"], tmp_path)


def test_select_dataset_stems_rejects_empty_dataset_directory(tmp_path: Path):
    with pytest.raises(ValueError, match="no dataset stems found"):
        dataset_module.select_dataset_stems([], tmp_path)


def test_select_dataset_stems_preserves_explicit_order(tmp_path: Path):
    (tmp_path / "alpha.yaml").write_text("items: []\n")
    (tmp_path / "beta.yaml").write_text("items: []\n")

    assert dataset_module.select_dataset_stems(["beta", "alpha"], tmp_path) == [
        "beta",
        "alpha",
    ]


def test_list_dataset_stems_cli_validates_and_preserves_explicit_order(tmp_path: Path):
    (tmp_path / "alpha.yaml").write_text("items: []\n")
    (tmp_path / "beta-name.yaml").write_text("items: []\n")
    script = Path(__file__).resolve().parents[1] / "scripts" / "list_dataset_stems.py"

    result = subprocess.run(
        [
            sys.executable,
            str(script),
            "--datasets-dir",
            str(tmp_path),
            "beta-name",
            "alpha",
        ],
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0
    assert result.stdout.splitlines() == ["beta-name", "alpha"]
