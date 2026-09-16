"""Runtime-side half of the LayerEnum registration guard.

``SparkTableStorageFormat`` and ``TableStorageDescriptorEnum`` are keyed by layer
and live in this package. PR 28513 was exactly this failure: ``consumption`` was
missing from ``SparkTableStorageFormat`` and ``TableLoaderPipeline.run()`` raised
at run time.

The compiler/airflow/core registries are covered by the sibling test in
``packages/bietlejuice-compiler/test/unit/ci_cd/source_layer_validation/test_layer_registration_exhaustiveness.py``;
they cannot be imported here because bietlejuice-runtime is a standalone uv
project.
"""

import pytest

from bietlejuice.base.hive.table_storage_descriptor_enum import (
    TableStorageDescriptorEnum,
)
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.spark.spark_table_storage_format import SparkTableStorageFormat

# Layers intentionally absent from a registry, with the reason. Anything not
# listed here must be registered.
_NO_SPARK_STORAGE = frozenset(
    {
        # Not workflow layers, so TableLoaderPipeline never resolves a storage
        # format for them.
        LayerEnum.TRANSACTIONAL,
        LayerEnum.QUBE,
        LayerEnum.WONKA,
        # Not a workflow layer yet; do not guess a CDC storage format.
        LayerEnum.INGESTION,
    }
)

_NO_STORAGE_DESCRIPTOR = frozenset(
    {
        # Hive structure sync only runs for the datalake/DW layers below; the
        # rest either bypass Hive entirely or are not Hive-registered.
        LayerEnum.TRANSACTIONAL,
        LayerEnum.DW_STAGING,
        LayerEnum.REVERSE,
        LayerEnum.QUBE,
        LayerEnum.WONKA,
        # Delta workflows always pass --bypass-hive, so consumption never reaches
        # sync_metastore_table_structure today. Left unmapped deliberately rather
        # than guessing a format.
        LayerEnum.CONSUMPTION,
        # Not a workflow layer yet; TRANSACTIONAL is already unmapped here.
        LayerEnum.INGESTION,
    }
)


def _expected(exclusions: frozenset) -> list[LayerEnum]:
    return [layer for layer in LayerEnum if layer not in exclusions]


@pytest.mark.parametrize("layer", _expected(_NO_SPARK_STORAGE), ids=lambda x: x.value)
def test_every_workflow_layer_has_a_spark_storage_format(layer):
    # act / assert — get_storage raises RuntimeError for an unregistered layer
    assert SparkTableStorageFormat.get_storage(layer.value) is not None


@pytest.mark.parametrize(
    "layer", _expected(_NO_STORAGE_DESCRIPTOR), ids=lambda x: x.value
)
def test_every_hive_synced_layer_has_a_storage_descriptor(layer):
    # act
    descriptor = TableStorageDescriptorEnum.from_layer(layer.value)

    # assert — None propagates into Hive registration as a null SerDe
    assert descriptor is not None
