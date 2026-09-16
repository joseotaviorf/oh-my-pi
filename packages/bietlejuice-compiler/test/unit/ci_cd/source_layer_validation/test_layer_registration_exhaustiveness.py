"""Compiler-side half of the LayerEnum registration guard.

Adding a member to ``LayerEnum`` is not enough on its own — every layer-keyed
registry has to learn about it too, and the failure modes are easy to miss in
review:

- ``KeyError`` at DAG build or Spark load (loud, caught quickly)
- ``.get()`` returning ``None``, which silently degrades — a validator that skips
  the DAG and reports green, or a ``database_name`` that is never checked

PR 28513 was the loud kind: ``consumption`` was missing from
``SparkTableStorageFormat`` and the Spark job raised at run time. The silent kind
is worse, so absence here is a failure unless listed below with a reason.

Sibling guards, split by package boundary:

- ``packages/bietlejuice-core/test/unit/base/test_layer_registration_exhaustiveness.py``
- ``packages/bietlejuice-airflow/test/unit/test_layer_registration_exhaustiveness.py``
- ``packages/bietlejuice-runtime/test/unit/base/test_layer_registration_exhaustiveness.py``
"""

import sys
from pathlib import Path

import pytest

from bietlejuice.base.pipeline.layer_enum import LayerEnum

sys.path.insert(0, str(Path(__file__).resolve().parents[6]))

from scripts.ci_cd.source_layer_validation.layer_policy_matrix import (  # noqa: E402
    ALLOWED_SOURCE_LAYERS_BY_OUTPUT,
)
from scripts.ci_cd.validate_dags_dependencies import LAYERS  # noqa: E402
from scripts.services.metadata_file_service import _DB_NAME_FORMULA  # noqa: E402

# Layers intentionally absent from a registry, with the reason. Anything not
# listed here must be registered.

_NO_POLICY_MATRIX_ENTRY = frozenset(
    {
        # Never appear as workflow.layer, so they are never an output layer.
        LayerEnum.TRANSACTIONAL,
        LayerEnum.CLEAN_STAGING,
        LayerEnum.DW_STAGING,
        LayerEnum.WONKA,
        # Not yet a workflow layer; see LayerEnum docstring.
        LayerEnum.INGESTION,
    }
)

_NO_DB_NAME_FORMULA = frozenset(
    {
        # Metadata files are not required for these layers.
        LayerEnum.REVERSE,
        LayerEnum.QUBE,
        LayerEnum.WONKA,
        # Not a workflow layer yet; no metadata/ingestion/ files exist.
        LayerEnum.INGESTION,
    }
)

_NO_QUERY_PATH_SEGMENT = frozenset(
    {
        # validate_dags_dependencies only parses queries/<layer>/ folders that
        # exist in the repo.
        LayerEnum.TRANSACTIONAL,
        LayerEnum.CLEAN_STAGING,
        LayerEnum.DW_STAGING,
        LayerEnum.REVERSE,
        LayerEnum.QUBE,
        LayerEnum.WONKA,
        LayerEnum.INGESTION,
    }
)


def _expected(exclusions: frozenset) -> list:
    return [layer for layer in LayerEnum if layer not in exclusions]


@pytest.mark.parametrize(
    "layer", _expected(_NO_POLICY_MATRIX_ENTRY), ids=lambda x: x.value
)
def test_every_output_layer_is_in_the_policy_matrix(layer):
    # assert — a missing key makes allowed_layers_for_output return None, and the
    # caller then skips the DAG entirely, so CI reports green without checking it
    assert layer.value in ALLOWED_SOURCE_LAYERS_BY_OUTPUT


@pytest.mark.parametrize("layer", _expected(_NO_DB_NAME_FORMULA), ids=lambda x: x.value)
def test_every_layer_requiring_metadata_has_a_db_name_formula(layer):
    # assert — None short-circuits the database_name check, leaving it unvalidated
    assert _DB_NAME_FORMULA.get(layer.value) is not None


@pytest.mark.parametrize(
    "layer", _expected(_NO_QUERY_PATH_SEGMENT), ids=lambda x: x.value
)
def test_every_query_folder_layer_is_parseable(layer):
    # assert — an unrecognised path segment misattributes the dag/table when
    # building the dependency graph
    assert layer.value in LAYERS
