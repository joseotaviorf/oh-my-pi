import pytest

from bietlejuice.base.airflow.dag_builders.main_builder.factories.base_factory import (
    BaseFactory,
)


@pytest.fixture(scope="function")
def base_factory():
    BaseFactory.__abstractmethods__ = set()
    return BaseFactory({}, {"type": "workflow_type"}, {})
