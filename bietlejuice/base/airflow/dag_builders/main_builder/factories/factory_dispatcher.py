from bietlejuice.base.airflow.dag_builders.main_builder.factories.base_factory import (
    BaseFactory,
)
from bietlejuice.base.airflow.dag_builders.main_builder.factories.dw_factory import (
    DWFactory,
)
from bietlejuice.base.airflow.dag_builders.main_builder.factories.raw_factory import (
    RawFactory,
)
from bietlejuice.base.airflow.dag_builders.main_builder.factories.metric_factory import (
    MetricFactory,
)
from bietlejuice.base.airflow.dag_builders.main_builder.factories.enrich_factory import (
    EnrichFactory,
)
from bietlejuice.base.airflow.dag_builders.main_builder.factories.clean_factory import (
    CleanFactory,
)
from bietlejuice.base.pipeline import LayerEnum


class FactoryDispatcher:
    """
    Class responsible for mapping the factories by layer and finding
    the respective one according to the DAG's layer.
    """

    FACTORY_CLASSES_MAPPING_BY_LAYER = {
        LayerEnum.RAW: RawFactory,
        LayerEnum.CLEAN: CleanFactory,
        LayerEnum.ENRICH: EnrichFactory,
        LayerEnum.DW: DWFactory,
        LayerEnum.METRIC: MetricFactory,
    }

    def __init__(self, layer: LayerEnum) -> None:
        self.layer = layer

    def get_factory(self, dag_args: dict, workflow_args: dict, cluster_args: dict):
        """Gets the factory class based on the DAG layer."""

        factory_class = self.__dispatch_factory_class()
        return factory_class(dag_args, workflow_args, cluster_args)

    def __dispatch_factory_class(self) -> BaseFactory:
        self.__validate_if_layer_factory_exits()
        return self.FACTORY_CLASSES_MAPPING_BY_LAYER.get(self.layer)

    def __validate_if_layer_factory_exits(self) -> None:
        if self.layer not in list(self.FACTORY_CLASSES_MAPPING_BY_LAYER):
            raise ValueError(
                f"m=__validate_if_layer_factory_exits, msg=There is not a Factory mapped"
                f" for the layer specified in the DAG declaration file, "
                f"mapped_layer_factories: {list(self.FACTORY_CLASSES_MAPPING_BY_LAYER)}"
            )
