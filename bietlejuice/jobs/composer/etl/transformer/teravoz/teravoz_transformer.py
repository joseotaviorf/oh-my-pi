from collections import OrderedDict
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.etl.transformer import Transformer

logger = QuintoAndarLogger("TeravozTransformer")


class TeravozTransformer(Transformer):
    @logger
    def __init__(self, env, athena_metastore_service):
        super().__init__(env, "teravoz", athena_metastore_service)
        self.env = env

    @logger
    def create_athena_table(self, datalake_layer, table_name):

        partition_by = ["year", "month", "day"]

        super().create_athena_table(
            table_name=table_name,
            datalake_layer=datalake_layer,
            partition_by=partition_by,
        )

    @logger
    def add_partition(self, datalake_layer, table_name, execution_date):
        dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
        partition_by_dict = OrderedDict(
            [
                ("year", dt_execution.year),
                ("month", dt_execution.month),
                ("day", dt_execution.day),
            ]
        )

        super().add_partition(table_name, datalake_layer, partition_by_dict)

    @logger
    def create_dataframe_from_datalake_sql_file(self, file_name, execution_date):
        # filter by day
        dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
        dict_format_query = {
            "year": dt_execution.year,
            "month": dt_execution.month,
            "day": dt_execution.day,
        }

        df = super().create_dataframe_from_datalake_sql_file(
            file_name, dict_format_query
        )

        return df
