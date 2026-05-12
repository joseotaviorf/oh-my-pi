from dependency_injector import containers, providers

from bietlejuice.base.spark.spark_dataframe_service import SparkDataFrameService


class Services(containers.DeclarativeContainer):
    spark_dataframe_service = providers.Factory(SparkDataFrameService)
