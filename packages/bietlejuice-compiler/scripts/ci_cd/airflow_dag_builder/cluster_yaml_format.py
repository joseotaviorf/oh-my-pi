"""YAML formatting helpers for *_cluster.yml generation and validation."""

from __future__ import annotations

import yaml

# Prevent yaml.dump from folding long spark_conf keys (e.g. Jinja catalog.namespace).
YAML_DUMP_WIDTH = 10_000

_FOLDED_CATALOG_NAMESPACE_MARKER = "environment\n        }}"


def dump_cluster_yaml(document: dict) -> str:
    """Dump cluster document YAML without folding long Jinja spark_conf values."""
    text = yaml.dump(
        document,
        default_flow_style=False,
        sort_keys=False,
        allow_unicode=True,
        width=YAML_DUMP_WIDTH,
    )
    if not text.endswith("\n"):
        text += "\n"
    return text


def assert_no_folded_catalog_namespace(text: str) -> None:
    """Reject PyYAML-folded catalog.namespace Jinja (broken across two lines)."""
    if _FOLDED_CATALOG_NAMESPACE_MARKER in text:
        raise ValueError(
            "folded spark.databricks.sql.initial.catalog.namespace Jinja "
            "(must stay on one line)"
        )
