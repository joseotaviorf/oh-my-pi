"""Write validation: blocks into QuintoML Wonka prod.yml files."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.airflow.cluster_config_resolver import (
    validation_resolves_to_prod_spec,
)
from bietlejuice.services.configuration_service import ConfigurationService

from .cluster_validation_mapping import ValidationClusterSpec
from .cluster_yaml_format import dump_cluster_yaml
from .rightsizing_validation_config import (
    _extract_top_level_section_text,
    _normalize_cluster_file_text,
    format_validation_section_yaml,
    validation_cluster_dict_from_spec,
)

LOGGER = QuintoAndarLogger("wonka_validation_config")


def validation_doc_from_spec(spec: ValidationClusterSpec) -> dict[str, Any]:
    validation_block: dict[str, Any] = {
        "cluster": validation_cluster_dict_from_spec(spec),
    }
    if spec.allow_custom_spark_job:
        validation_block["allow_custom_spark_job"] = True
    return validation_block


def write_validation_to_wonka_prod_yml(
    prod_yml_path: Path,
    validation_doc: dict[str, Any],
) -> None:
    """Upsert top-level validation: in a QuintoML prod.yml without touching cluster:."""
    original_text = prod_yml_path.read_text(encoding="utf-8")
    validation_text = _extract_top_level_section_text(original_text, "validation")
    text_without_validation = (
        original_text.replace(validation_text, "") if validation_text else original_text
    )
    while "\n\n\n" in text_without_validation:
        text_without_validation = text_without_validation.replace("\n\n\n", "\n\n")

    validation_yaml = format_validation_section_yaml(validation_doc)
    new_text = text_without_validation.rstrip("\n") + "\n\n" + validation_yaml

    prod_yml_path.parent.mkdir(parents=True, exist_ok=True)
    prod_yml_path.write_text(
        _normalize_cluster_file_text(new_text),
        encoding="utf-8",
    )


def remove_validation_from_wonka_prod_yml(prod_yml_path: Path) -> bool:
    """Drop validation: from prod.yml; returns True when the file changed."""
    if not prod_yml_path.exists():
        return False
    original_text = prod_yml_path.read_text(encoding="utf-8")
    validation_text = _extract_top_level_section_text(original_text, "validation")
    if validation_text is None:
        return False

    new_text = original_text.replace(validation_text, "")
    while "\n\n\n" in new_text:
        new_text = new_text.replace("\n\n\n", "\n\n")
    prod_yml_path.write_text(
        _normalize_cluster_file_text(new_text.rstrip("\n") + "\n"),
        encoding="utf-8",
    )
    return True


def load_wonka_prod_declaration(prod_yml_path: Path) -> dict | None:
    try:
        doc = yaml.safe_load(prod_yml_path.read_text(encoding="utf-8"))
        return doc if isinstance(doc, dict) else None
    except (OSError, yaml.YAMLError) as exc:
        LOGGER.warning("Failed to parse %s: %s", prod_yml_path, exc)
        return None


def wonka_validation_is_noop(prod_yml_path: Path) -> bool:
    """True when on-disk validation resolves to prod spec (Wonka prod.yml)."""
    doc = load_wonka_prod_declaration(prod_yml_path)
    if not doc:
        return False
    prod_cluster = doc.get("cluster")
    validation = doc.get("validation")
    validation_cluster = (
        validation.get("cluster") if isinstance(validation, dict) else None
    )
    if not isinstance(prod_cluster, dict) or not isinstance(validation_cluster, dict):
        return False
    try:
        return validation_resolves_to_prod_spec(
            prod_cluster, validation_cluster, ConfigurationService()
        )
    except (ValueError, IndexError):
        return False


def promote_wonka_validation_to_prod(prod_yml_path: Path) -> dict[str, Any] | None:
    """Merge validation topology into prod custom_configurations; keep wonka_cluster type."""
    original_text = prod_yml_path.read_text(encoding="utf-8")
    doc = yaml.safe_load(original_text) or {}
    if not isinstance(doc, dict) or "validation" not in doc:
        return None

    previous_cluster = doc.get("cluster", {})
    if not isinstance(previous_cluster, dict):
        previous_cluster = {}

    validation_cluster = doc["validation"].get("cluster")
    if not isinstance(validation_cluster, dict):
        return None

    val_custom = validation_cluster.get("custom_configurations") or {}
    if not isinstance(val_custom, dict):
        val_custom = {}

    prod_cluster = dict(previous_cluster)
    prod_custom = dict(prod_cluster.get("custom_configurations") or {})
    prod_custom.update(val_custom)
    prod_cluster["custom_configurations"] = prod_custom

    validation_text = _extract_top_level_section_text(original_text, "validation")
    text_without_validation = (
        original_text.replace(validation_text, "") if validation_text else original_text
    )
    while "\n\n\n" in text_without_validation:
        text_without_validation = text_without_validation.replace("\n\n\n", "\n\n")

    cluster_yaml = dump_cluster_yaml({"cluster": prod_cluster}).rstrip("\n")
    cluster_text = _extract_top_level_section_text(text_without_validation, "cluster")
    if cluster_text:
        new_text = text_without_validation.replace(cluster_text, cluster_yaml + "\n")
    else:
        new_text = cluster_yaml + "\n" + text_without_validation

    prod_yml_path.write_text(
        _normalize_cluster_file_text(new_text.rstrip("\n") + "\n"),
        encoding="utf-8",
    )
    return previous_cluster
