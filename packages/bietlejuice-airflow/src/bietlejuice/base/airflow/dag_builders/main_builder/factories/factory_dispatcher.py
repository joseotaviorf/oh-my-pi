from airflow.datasets import BaseDataset

from bietlejuice.base.airflow.dag_builders.main_builder.factories.base_factory import (
    BaseFactory,
)
from bietlejuice.base.airflow.dag_builders.main_builder.factories.clean_factory import (
    CleanFactory,
)
from bietlejuice.base.airflow.dag_builders.main_builder.factories.core_factory import (
    CoreFactory,
)
from bietlejuice.base.airflow.dag_builders.main_builder.factories.dw_factory import (
    DWFactory,
)
from bietlejuice.base.airflow.dag_builders.main_builder.factories.enrich_factory import (
    EnrichFactory,
)
from bietlejuice.base.airflow.dag_builders.main_builder.factories.metric_factory import (
    MetricFactory,
)
from bietlejuice.base.airflow.dag_builders.main_builder.factories.qube_factory import (
    QubeFactory,
)
from bietlejuice.base.airflow.dag_builders.main_builder.factories.raw_factory import (
    RawFactory,
)
from bietlejuice.base.airflow.dag_builders.main_builder.factories.reverse_factory import (
    ReverseFactory,
)
from bietlejuice.base.airflow.dag_builders.main_builder.factories.wonka_factory import (
    WonkaFactory,
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
        LayerEnum.CORE: CoreFactory,
        LayerEnum.ENRICH: EnrichFactory,
        # Consumption reuses EnrichFactory: same query_delta / metadata path;
        # naming + source-layer policy differ via LayerEnum / CONSUMPTION_SCHEMAS.
        LayerEnum.CONSUMPTION: EnrichFactory,
        # Transformation likewise reuses EnrichFactory — the execution path is
        # identical to enrich; only naming and source-layer policy differ.
        # INGESTION is deliberately absent: like TRANSACTIONAL it is not yet a
        # workflow layer, so declaring it should fail loudly here until the CDC
        # multi-layer design lands.
        LayerEnum.TRANSFORMATION: EnrichFactory,
        LayerEnum.DW: DWFactory,
        LayerEnum.METRIC: MetricFactory,
        LayerEnum.REVERSE: ReverseFactory,
        LayerEnum.WONKA: WonkaFactory,
        LayerEnum.QUBE: QubeFactory,
    }

    def __init__(self, layer: LayerEnum) -> None:
        self.layer = layer

    def get_factory(
        self,
        dag_args: dict,
        workflow_args: dict,
        cluster_args: dict,
        dataset_dependencies: BaseDataset = None,
        **kwargs,
    ):
        """Gets the factory class based on the DAG layer."""

        factory_class = self.__dispatch_factory_class()
        return factory_class(
            dag_args,
            workflow_args,
            cluster_args,
            dataset_dependencies,
            **kwargs,
        )

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
