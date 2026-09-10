import time
from typing import Dict, List, Union

from pyspark.sql import DataFrame, functions
from pyspark.sql.types import StringType, StructField, StructType
from quintoandar_gsheets_api_client.consumer import GoogleSheetsReader
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.spark.spark_dataframe_service import SparkDataFrameService
from bietlejuice.formatters.string_formatter import StringFormatter

logger = QuintoAndarLogger("GsheetsConsumer")


class GsheetsConsumer(GoogleSheetsReader):
    """
    Gets data from Gsheet, apply internal minimal patterns and returns Spark
    DataFrame. This consumer depends on quintoandar_gsheets_api_client library.

    :param gsheets_client: A client to handle the Gsheets API already authenticated
    :type gsheets_client: GoogleSheetsClient
    :param spark_client: A client to handle the Spark connection
    :type spark_client: SparkClient
    """

    def __init__(self, gsheets_client, spark_client):
        super().__init__(gsheets_client)
        self.spark_client = spark_client

    def __generate_schema(
        self, data: Union[List[Dict], List], sheet_name: str
    ) -> StructType:
        """
        Generates the schema using the gsheet's columns names.

        Build the schema for this gsheet and defines all the columns types
        as strings for the temporary table load.
        :param data: data return from gsheets client for specific sheet
        :param sheet_name: Sheet name for data
        """
        if len(data):
            columns = data[0].keys()
            type_array = [
                StructField(column_name, StringType()) for column_name in columns
            ]
            schema = StructType(type_array)
            return schema

        raise ValueError(f"m=__generate_schema, msg=Table {sheet_name} Empty!")

    def __preload_gsheet(
        self, sheet_name: str, sheet_id: str, preload_time_in_seconds: int
    ) -> None:
        """
        This method makes an API call to preload the gsheet, and then waits the amount of seconds
        specified by sheet_details['preload_time_in_seconds']
        :param sheet_name: Sheet name for data
        :param sheet_id: Sheet ID for data
        :param preload_time_in_seconds: If data needs to be preloaded before fetching
        """
        logger.info("m=__preload_gsheet, msg=Stating preload o gsheet")
        preload_client_response = self.read(sheet_name, sheet_id)
        logger.info(
            f"""
            m=__preload_gsheet, msg=Initial length of {len(preload_client_response)}. Waiting for
            {preload_time_in_seconds} seconds to preload the gsheet {sheet_name}"
        """
        )
        time.sleep(preload_time_in_seconds)

    @staticmethod
    def _records_from_grid(all_values: List[List[str]], header_row: int) -> List[Dict]:
        """
        Build row dicts from a worksheet grid using a 1-based header row index.

        :param all_values: Full worksheet grid from gspread ``get_all_values``.
        :param header_row: 1-based row number that contains column headers.
        """
        if header_row < 1:
            raise ValueError(
                f"m=_records_from_grid, header_row={header_row}, "
                "msg=header_row must be >= 1"
            )
        if len(all_values) < header_row:
            raise ValueError(
                f"m=_records_from_grid, header_row={header_row}, "
                f"row_count={len(all_values)}, msg=Sheet has fewer rows than header_row"
            )

        headers = all_values[header_row - 1]
        records = []
        for row in all_values[header_row:]:
            if not any(str(cell).strip() for cell in row):
                continue
            padded_row = list(row) + [""] * max(0, len(headers) - len(row))
            records.append(
                {headers[index]: padded_row[index] for index in range(len(headers))}
            )
        return records

    def _read_sheet_records(
        self, sheet_name: str, sheet_id: str, header_row: int = 1
    ) -> List[Dict]:
        """
        Read worksheet rows as dict records, optionally using a non-first header row.
        """
        if header_row == 1:
            return self.read(sheet_name, sheet_id)

        working_sheet = self.google_sheets_client.gsheets.open_by_key(sheet_id)
        sheet = working_sheet.worksheet(sheet_name)
        return self._records_from_grid(sheet.get_all_values(), header_row)

    def __columns_to_alphanumeric_snake_case(self, df: DataFrame) -> DataFrame:
        """
        This method applies changes to dataframe column names.
        :param df: Spark Dataframe with google sheets data.
        """
        old_columns = df.columns
        new_columns = [
            StringFormatter.set_alphanumeric_snake_case(column)
            for column in old_columns
        ]
        return df.toDF(*new_columns)

    def parse_data_on_dataframe(
        self, sheet_data: Union[List[Dict], List], table_name: str, is_partitioned: bool
    ) -> DataFrame:
        """
        This method parses Gsheets API data for specific table_name and returns
        as a Pyspark Dataframe

        :param sheet_data: data return from gsheets client for specific sheet
        :param table_name: Sheet name for data
        :param is_partitioned: If data needs to be partitioned
        :return: pyspark.dataframe
        """

        schema = self.__generate_schema(sheet_data, table_name)
        df = self.spark_client.create_dataframe(sheet_data, schema=schema)
        df = df.withColumn("ts_load", functions.current_timestamp())
        if is_partitioned:
            df = (
                SparkDataFrameService()
                .input(df)
                .create_year_month_day_columns_from_dataframe_column("ts_load")
                .output()
            )
        df = self.__columns_to_alphanumeric_snake_case(df)

        return df

    @logger(exclude_return=True)
    def get_sheet_df(
        self,
        sheet_name: str,
        sheet_id: str,
        table_name: str,
        is_partitioned: bool = False,
        preload_time_in_seconds: int = None,
        header_row: int = 1,
    ) -> DataFrame:
        """
        :param sheet_name: Sheet name for data
        :param sheet_id: Sheet ID for data
        :param table_name: Sheet clean table name
        :param is_partitioned: If data needs to be partitioned
        :param preload_time_in_seconds: If data needs to be preloaded before fetching
        :param header_row: 1-based row number used as column headers (default: first row)
        """
        if preload_time_in_seconds:
            self.__preload_gsheet(
                sheet_name=sheet_name,
                sheet_id=sheet_id,
                preload_time_in_seconds=preload_time_in_seconds,
            )

        sheet_data = self._read_sheet_records(sheet_name, sheet_id, header_row)
        df = self.parse_data_on_dataframe(sheet_data, table_name, is_partitioned)

        return df
