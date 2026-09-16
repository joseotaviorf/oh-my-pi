"""Core-side half of the LayerEnum registration guard.

Adding a member to ``LayerEnum`` is not enough on its own — every layer-keyed
registry has to learn about it too. ``MetastoreMappingFactory`` raises
``KeyError`` for an unmapped layer, and ``TaskGroupMethodFactory`` returns
``None``, which only surfaces later as "NoneType is not callable".

Sibling guards, split by package boundary:

- ``packages/bietlejuice-airflow/test/unit/test_layer_registration_exhaustiveness.py``
- ``packages/bietlejuice-compiler/test/unit/ci_cd/source_layer_validation/test_layer_registration_exhaustiveness.py``
- ``packages/bietlejuice-runtime/test/unit/base/test_layer_registration_exhaustiveness.py``
"""

import pytest

from bietlejuice.base.airflow.task_group_method_factory import TaskGroupMethodFactory
from bietlejuice.base.db.metastore_mapping_factory import MetastoreMappingFactory
from bietlejuice.base.pipeline.layer_enum import LayerEnum

# Layers intentionally absent from a registry, with the reason. Anything not
# listed here must be registered.

_NO_METASTORE_MAPPER = frozenset(
    {
        # Not a workflow layer yet; TRANSACTIONAL already maps the same physical
        # store. See LayerEnum docstring.
        LayerEnum.INGESTION,
    }
)

_NO_SQL_TASK_GROUP = frozenset(
    {
        # Task groups are built from SQL files only for the layers below; the
        # rest use dedicated workflows or are not SQL-driven at all.
        LayerEnum.TRANSACTIONAL,
        LayerEnum.RAW,
        LayerEnum.CLEAN_STAGING,
        LayerEnum.CORE,
        LayerEnum.QUBE,
        LayerEnum.WONKA,
        LayerEnum.CONSUMPTION,
        # Enrich-path workflows build tables via EnrichQueryWorkflow._get_tables,
        # not from the SQL-file task-group factory. Mapping TRANSFORMATION to
        # build_enrich_task_group would be unreachable and, if reached, wrong:
        # that method hardcodes LayerEnum.ENRICH.
        LayerEnum.TRANSFORMATION,
        # Not yet a workflow layer; see LayerEnum docstring.
        LayerEnum.INGESTION,
    }
)


def _expected(exclusions: frozenset) -> list:
    return [layer for layer in LayerEnum if layer not in exclusions]


@pytest.mark.parametrize(
    "layer", _expected(_NO_METASTORE_MAPPER), ids=lambda x: x.value
)
def test_every_layer_has_a_metastore_mapper(layer):
    # act / assert — an unmapped layer raises KeyError here
    assert MetastoreMappingFactory.get_mapper_by_layer(layer, "some_source", "a-bucket")


@pytest.mark.parametrize("layer", _expected(_NO_SQL_TASK_GROUP), ids=lambda x: x.value)
def test_every_sql_driven_layer_has_a_task_group_method(layer):
    # act
    method = TaskGroupMethodFactory.get_method_for_build_task_group_from_sql_files(
        layer.value
    )

    # assert — None becomes "NoneType is not callable" at the call site
    assert method is not None
