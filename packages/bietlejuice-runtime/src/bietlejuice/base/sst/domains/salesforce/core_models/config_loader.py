import json
from os import path
from typing import Any, Dict

import yaml
from hierarchical_conf.hierarchical_conf import HierarchicalConf

from bietlejuice.base.paths import BIETLEJUICE_CONFIG_ROOT
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService

_ASTRONOMER_DAGS_PREFIX = "astronomer/dags"


def _artifacts_bucket_name() -> str:
    global_confs = HierarchicalConf([BIETLEJUICE_CONFIG_ROOT])
    artifacts_bucket = global_confs.get_config("artifacts_bucket")
    return artifacts_bucket.replace("s3://", "").strip("/")


def load_table_spec_from_relative_path(relative_path: str) -> Dict[str, Any]:
    """
    Load a table spec YAML from the Astro DAG bundle on the artifacts bucket.

    ``relative_path`` is relative to ``astronomer/dags/`` (e.g.
    ``core/core_support_journey/tables/cases.yml``), published by
    ``upload-dag-packages-dags-s3-*``.
    """
    bucket = _artifacts_bucket_name()
    s3_key = path.join(_ASTRONOMER_DAGS_PREFIX, relative_path)
    content = DAGPackagesPathService._read_file_from_s3_boto3(bucket, s3_key)
    if not content:
        raise FileNotFoundError(
            f"Table spec file was not found or is empty: s3://{bucket}/{s3_key}. "
            "Ensure upload-dag-packages-dags-s3 has run for this DAG package."
        )
    spec = yaml.safe_load(content)
    if not spec:
        raise FileNotFoundError(f"Table spec file is empty: s3://{bucket}/{s3_key}")
    return spec


def table_spec_from_cfg(cfg: Any) -> Dict[str, Any]:
    """
    Load the table specification from the configuration.

    Prefer ``table_config_relative_path`` (Astro DAG bundle on artifacts S3) for
    production EMR runs. ``table_config_json`` (dict or JSON string) remains for
    unit tests.
    """
    relative_path = getattr(cfg, "table_config_relative_path", None)
    if relative_path:
        return load_table_spec_from_relative_path(relative_path)

    table_config_json = getattr(cfg, "table_config_json", None)
    if isinstance(table_config_json, dict):
        return table_config_json
    if isinstance(table_config_json, str):
        return json.loads(table_config_json)

    raise ValueError("cfg must provide table_config_relative_path or table_config_json")
