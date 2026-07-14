"""Unit tests for ``DAGPackagesPathService.get_config_file_content_in_spark_jobs``.

This reader loads a co-located config file shipped under ``spark_jobs/{dag_name}/``
(e.g. the Agents alert registry YAML). It mirrors the EMR engine switch of the
sibling ``get_query_file_content_in_spark_jobs`` reader:
``RuntimeDetector.is_emr()`` forces ``engine="boto3"``.

``bietlejuice.base.spark.runtime_detector`` is shipped by *bietlejuice-runtime*,
not core, and the reader imports it lazily inside the method. In the core test
env that module tree does not exist, so we stub
``bietlejuice.base.spark`` / ``bietlejuice.base.spark.runtime_detector`` in
``sys.modules`` around each call.

Run::

    pytest packages/bietlejuice-core/test/unit/base/service/test_dag_packages_path_service.py -q
"""

import sys
from contextlib import contextmanager
from os import path
from unittest import mock
from unittest.mock import MagicMock

import pytest

from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService


@contextmanager
def _stubbed_runtime_detector(is_emr: bool):
    """Provide a stub ``RuntimeDetector`` for the method's lazy import."""
    runtime_detector_module = MagicMock()
    runtime_detector_module.RuntimeDetector.is_emr.return_value = is_emr
    stubs = {
        "bietlejuice.base.spark": MagicMock(),
        "bietlejuice.base.spark.runtime_detector": runtime_detector_module,
    }
    with mock.patch.dict(sys.modules, stubs):
        yield


def test_get_config_file_content_builds_relative_path_and_returns_content():
    with (
        _stubbed_runtime_detector(is_emr=False),
        mock.patch.object(
            DAGPackagesPathService, "_read_dag_package_file_from_s3"
        ) as mock_read,
    ):
        mock_read.return_value = "alerts:\n  x: {}"

        result = DAGPackagesPathService.get_config_file_content_in_spark_jobs(
            dag_name="enrich_agents_alerts", file_name="alerts_registry.yml"
        )

    assert result == "alerts:\n  x: {}"
    _, kwargs = mock_read.call_args
    assert kwargs["sql_file_relative_path"] == path.join(
        "spark_jobs", "enrich_agents_alerts", "alerts_registry.yml"
    )


def test_get_config_file_content_uses_boto3_on_emr_with_default_engine():
    with (
        _stubbed_runtime_detector(is_emr=True),
        mock.patch.object(
            DAGPackagesPathService, "_read_dag_package_file_from_s3"
        ) as mock_read,
    ):
        mock_read.return_value = "alerts: {}"

        DAGPackagesPathService.get_config_file_content_in_spark_jobs(
            dag_name="enrich_agents_alerts", file_name="alerts_registry.yml"
        )

    _, kwargs = mock_read.call_args
    assert kwargs["engine"] == "boto3"


def test_get_config_file_content_forces_boto3_on_emr_even_if_spark_requested():
    with (
        _stubbed_runtime_detector(is_emr=True),
        mock.patch.object(
            DAGPackagesPathService, "_read_dag_package_file_from_s3"
        ) as mock_read,
    ):
        mock_read.return_value = "alerts: {}"

        DAGPackagesPathService.get_config_file_content_in_spark_jobs(
            dag_name="enrich_agents_alerts",
            file_name="alerts_registry.yml",
            engine="spark",
        )

    _, kwargs = mock_read.call_args
    assert kwargs["engine"] == "boto3"


def test_get_config_file_content_keeps_databricks_volume_when_not_emr():
    with (
        _stubbed_runtime_detector(is_emr=False),
        mock.patch.object(
            DAGPackagesPathService, "_read_dag_package_file_from_s3"
        ) as mock_read,
    ):
        mock_read.return_value = "alerts: {}"

        DAGPackagesPathService.get_config_file_content_in_spark_jobs(
            dag_name="enrich_agents_alerts", file_name="alerts_registry.yml"
        )

    _, kwargs = mock_read.call_args
    assert kwargs["engine"] == "databricks_volume"


@pytest.mark.parametrize("empty_content", ["", None], ids=["empty_string", "none"])
def test_get_config_file_content_raises_file_not_found_when_empty(empty_content):
    with (
        _stubbed_runtime_detector(is_emr=False),
        mock.patch.object(
            DAGPackagesPathService, "_read_dag_package_file_from_s3"
        ) as mock_read,
    ):
        mock_read.return_value = empty_content

        with pytest.raises(FileNotFoundError):
            DAGPackagesPathService.get_config_file_content_in_spark_jobs(
                dag_name="enrich_agents_alerts", file_name="alerts_registry.yml"
            )
