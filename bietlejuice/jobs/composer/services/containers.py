from dependency_injector import providers, containers
from bietlejuice.jobs.composer.base.spark import SparkDataFrameService


class Services(containers.DeclarativeContainer):
    spark_dataframe_service = providers.Factory(SparkDataFrameService)
