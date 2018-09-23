import time
from datetime import datetime

from qa_python_utils.aws.athena import AthenaClient


class StitchTransferRaw(object):
    def __init__(self, bucket, execution_date, integration, database, table, date_field):
        self.athena = AthenaClient(bucket)
        self.execution_date = execution_date
        self.integration = integration
        self.database = database
        self.table = table
        self.date_field = date_field

    def fetch_data(self):
        partition = datetime.strftime(self.execution_date, "%Y-%m-%d")
        self.athena.add_partition(self.database, self.table, "dt='{}'".format(partition))

        query = """
            SELECT *, DATE(FROM_ISO8601_TIMESTAMP({date_field})) as created_at
            FROM {database}.{table}
            limit 10
        """.format(date_field=self.date_field,
                   integration=self.integration,
                   table=self.table,
                   database=self.database)

        dataframe = self.athena.execute_query_and_return_dataframe(query)
        date_group = dataframe['created_at'].unique()

        for item in date_group:
            splitted_df = dataframe.query("created_at == '{}'".format(item))
            path = "raw/market_cost/{integration}/{table}/acc={account}/dt={date_partititon}/{file_name}.parquet".format(
                integration=self.integration,
                table=self.table,
                account=self.integration,
                date_partititon=item,
                file_name=int(time.mktime(datetime.now().timetuple())) * 1000
            )


if __name__ == '__main__':
    transfer = StitchTransferRaw("5a-datalake", datetime.now(), "facebook_ads_supply_landlords", "stitch_test",
                                 "stitch_adsets", "created_time")
    transfer.fetch_data()
