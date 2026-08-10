"""Regression guard: EMR cluster base does not pin an Amazon Linux OS release.

The base was pinned in #27380 to stop clusters floating to AWS's latest
validated AMI, then rolled back in #27385 after the newer label had rollout
problems. Both pinned labels caused more trouble than the floating default, so
the base now omits ``emr_os_release_label`` and lets EMR pick the latest
validated AMI for the release label.

``translate()`` only emits ``OSReleaseLabel`` when the key is present, so
re-adding it here silently repins the whole fleet — hence this guard. A single
cluster can still pin deliberately via its own ``custom_configurations``.
"""

from pathlib import Path

import pytest
import yaml

_CONFIG_DIR = Path(__file__).parents[4] / "src" / "bietlejuice" / "config"


def _load_emr_cluster_base(conf_file_name: str) -> dict:
    path = _CONFIG_DIR / conf_file_name
    raw = yaml.safe_load(path.read_text())
    return raw["emr_cluster_base"]


@pytest.mark.parametrize("conf_file_name", ["prod_conf.yml", "forno_conf.yml"])
def test_emr_cluster_base_does_not_pin_os_release_label(conf_file_name: str) -> None:
    base = _load_emr_cluster_base(conf_file_name)
    assert "emr_os_release_label" not in base


@pytest.mark.parametrize("conf_file_name", ["prod_conf.yml", "forno_conf.yml"])
def test_emr_cluster_base_does_not_pin_custom_ami(conf_file_name: str) -> None:
    # emr_custom_ami_id is mutually exclusive with emr_os_release_label and
    # would pin the fleet just as hard.
    base = _load_emr_cluster_base(conf_file_name)
    assert "emr_custom_ami_id" not in base
