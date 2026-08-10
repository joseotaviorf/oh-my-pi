"""Regression guard: EMR cluster base pins Amazon Linux OS release."""

from pathlib import Path

import pytest
import yaml

_CONFIG_DIR = Path(__file__).parents[4] / "src" / "bietlejuice" / "config"
_PINNED_OS_RELEASE_LABEL = "2023.12.20260622.0"


def _load_emr_cluster_base(conf_file_name: str) -> dict:
    path = _CONFIG_DIR / conf_file_name
    raw = yaml.safe_load(path.read_text())
    return raw["emr_cluster_base"]


@pytest.mark.parametrize("conf_file_name", ["prod_conf.yml", "forno_conf.yml"])
def test_emr_cluster_base_pins_os_release_label(conf_file_name: str) -> None:
    base = _load_emr_cluster_base(conf_file_name)
    assert base.get("emr_os_release_label") == _PINNED_OS_RELEASE_LABEL
