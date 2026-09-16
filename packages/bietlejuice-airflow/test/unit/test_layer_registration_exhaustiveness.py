"""Airflow-side half of the LayerEnum registration guard.

Adding a member to ``LayerEnum`` is not enough on its own — every layer-keyed
registry has to learn about it too. ``FactoryDispatcher`` raises ``ValueError``
for an unmapped workflow layer, which is loud. ``DatasetService`` is the silent
kind: a missing template yields ``None`` and the table simply never emits an
Airflow dataset event, so lineage and alerting quietly lose it.

Sibling guards, split by package boundary:

- ``packages/bietlejuice-core/test/unit/base/test_layer_registration_exhaustiveness.py``
- ``packages/bietlejuice-compiler/test/unit/ci_cd/source_layer_validation/test_layer_registration_exhaustiveness.py``
- ``packages/bietlejuice-runtime/test/unit/base/test_layer_registration_exhaustiveness.py``
"""

import pytest

from bietlejuice.base.airflow.dag_builders.main_builder.factories.factory_dispatcher import (
    FactoryDispatcher,
)
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.services.dataset_service import DatasetService

# Layers intentionally absent from a registry, with the reason. Anything not
# listed here must be registered.

_NO_WORKFLOW_FACTORY = frozenset(
    {
        # Not workflow layers — they are storage/naming patterns produced by
        # other layers' workflows, never declared in workflow.layer.
        LayerEnum.TRANSACTIONAL,
        LayerEnum.CLEAN_STAGING,
        LayerEnum.DW_STAGING,
        # Not yet a workflow layer: declaring it should fail loudly until the CDC
        # multi-layer design lands. See LayerEnum docstring.
        LayerEnum.INGESTION,
    }
)

_NO_DATASET_NAME = frozenset(
    {
        # Not a workflow layer yet, so no task emits layer=ingestion params.
        # TRANSACTIONAL already covers the same physical store. See LayerEnum
        # docstring.
        LayerEnum.INGESTION,
    }
)


def _expected(exclusions: frozenset) -> list:
    return [layer for layer in LayerEnum if layer not in exclusions]


@pytest.mark.parametrize(
    "layer", _expected(_NO_WORKFLOW_FACTORY), ids=lambda x: x.value
)
def test_every_workflow_layer_has_a_factory(layer):
    # assert — a missing entry raises ValueError at DAG build time
    assert layer in FactoryDispatcher.FACTORY_CLASSES_MAPPING_BY_LAYER


@pytest.mark.parametrize("layer", _expected(_NO_DATASET_NAME), ids=lambda x: x.value)
def test_every_layer_has_a_dataset_database_template(layer):
    # assert — None means no dataset event is emitted for tables in this layer
    assert DatasetService._LAYER_TO_DATABASE_NAME.get(layer.value) is not None
