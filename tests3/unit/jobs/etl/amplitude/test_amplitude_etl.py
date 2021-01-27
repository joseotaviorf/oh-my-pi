import gzip
import zipfile
from datetime import datetime
from io import BytesIO

from pyspark.sql.functions import to_json


class TestAmplitudeEvents:
    def test_create_raw_events_df(self, amplitude_events, dataframe_service):
        # arrange
        json_file_content = '{"event_properties": {"a": 1, "b": 2}, "c": 3, ' \
                            '"server_upload_time": "2019-08-22"}'
        expected_df_schema = [
            ("event_properties", "string"),
            ("c", "bigint"),
            ("server_upload_time", "string"),
            ("year", "int"),
            ("month", "int"),
            ("day", "int"),
        ]

        # creating gzip_file with json content
        fgz = BytesIO()
        gzip_obj = gzip.GzipFile(filename="data.json.gz", mode="wb", fileobj=fgz)
        gzip_obj.write(json_file_content.encode())
        gzip_obj.close()

        # creating zipfile
        fz = BytesIO()
        zip_obj = zipfile.ZipFile(fz, "w")
        zip_obj.writestr("data.gz", fgz.getvalue())
        zip_obj.close()

        # act
        result_df = amplitude_events.create_raw_events_df(fz, dataframe_service)
        result_df_schema = result_df.dtypes

        # assert
        assert result_df_schema.sort(key=lambda tup: tup[0]) == expected_df_schema.sort(
            key=lambda tup: tup[0]
        )

    def test_create_clean_events_df(
        self, spark_context, spark_session, spark_sql_consumer, amplitude_events, dataframe_service
    ):
        # arrange
        data = [{"a": 1, "b": 2}]
        date = datetime(2019, 8, 22, 0, 0, 0, 0)

        df = spark_session.read.json(spark_context.parallelize(data, 1))
        spark_sql_consumer.set_query_result(df)
        expected_values = [date.year, date.month, date.day, "events"]
        spark_sql_consumer.query_expected_values(expected_values)

        # act
        result_df = amplitude_events.create_clean_events_df(
            date, spark_sql_consumer, dataframe_service, partition_by_list=['a']
        )

        # assert
        assert type(result_df) == type(df)

    def test_create_filtered_clean_events_df(
        self, spark_context, spark_session, spark_sql_consumer, amplitude_events, dataframe_service
    ):
        # arrange
        data = [
            {
                "event_properties": {"a": 1},
                "user_properties": {"b": 1},
                "year": 2019,
                "month": 8,
                "day": 22,
            }
        ]
        date = datetime(2019, 8, 22, 0, 0, 0, 0)
        event_type = "listing_page_viewed"

        df = spark_session.read.json(spark_context.parallelize(data, 1))
        df = df.withColumn("event_properties", to_json(df["event_properties"]))
        df = df.withColumn("user_properties", to_json(df["user_properties"]))

        spark_sql_consumer.set_query_result(df)
        expected_values = [date.year, date.month, date.day, event_type]
        spark_sql_consumer.query_expected_values(expected_values)

        expected_df_schema = [
            ("event_a", "bigint"),
            ("user_b", "bigint"),
            ("year", "int"),
            ("month", "int"),
            ("day", "int"),
        ]

        # act
        result_df = amplitude_events.create_filtered_clean_events_df(
            date, event_type, spark_sql_consumer, dataframe_service
        )
        result_df_schema = result_df.dtypes

        # assert
        assert result_df_schema.sort(key=lambda tup: tup[0]) == expected_df_schema.sort(
            key=lambda tup: tup[0]
        )
