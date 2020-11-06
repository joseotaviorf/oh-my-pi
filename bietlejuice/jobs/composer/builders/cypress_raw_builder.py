from datetime import datetime
from pyspark.sql.functions import lit, explode
from pyspark.sql.types import StructType, ArrayType
from bietlejuice.jobs.composer.base.spark import spark

from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("CypressRawBuilder")

FULL_FILE_PATH_LENGTH = 6


class CypressRawBuilder:
    def __init__(self, s3_consumer, s3_service, execution_date):
        self.s3_consumer = s3_consumer
        self.s3_service = s3_service
        self.s3_source_file_format = "json"
        self.execution_date = execution_date
        self.pwa_name = None

    def flatten(self, schema, prefix=None):
        fields = []
        for field in schema.fields:
            name = prefix + "." + field.name if prefix else field.name
            dtype = field.dataType
            if isinstance(dtype, ArrayType):
                dtype = dtype.elementType

            if isinstance(dtype, StructType):
                fields += self.flatten(dtype, prefix=name)
            else:
                fields.append(name)

        return fields

    def __split_str(self, str, split_condition):
        return [x for x in str.split(split_condition) if x != ""]

    def __parse_execution_date(self):
        parsed_date = datetime.strptime(self.execution_date, "%Y-%m-%d").date()
        return parsed_date

    def __get__path_date(self, file_path):
        return file_path.split("/")[4]

    def __filter_for_full_file_paths(self, file_paths):
        filtered_file_paths = [
            x
            for x in file_paths
            if len(self.__split_str(x, "/")) >= FULL_FILE_PATH_LENGTH
        ]
        return filtered_file_paths

    def __filter_for_json_file_paths(self, file_paths):
        filtered_file_paths = [x for x in file_paths if "json" in x]
        return filtered_file_paths

    def __file_is_from_today(self, file_path):
        path_date = self.__get__path_date(file_path)
        return path_date == self.execution_date

    def __filter_for_execution_date(self, file_paths):
        filtered_file_paths = [
            file_path
            for file_path in file_paths
            if self.__file_is_from_today(file_path)
        ]
        return filtered_file_paths

    def __append_partition_data(self, df):
        load_date = str(self.__parse_execution_date())
        df_with_pwa = df.withColumn("pwa", lit(self.pwa_name))
        df_with_dt = df_with_pwa.withColumn("dt", lit(load_date))
        return df_with_dt

    def __get_tests_data(self, df):
        tests = df.select(explode("tests"))
        tests = tests.select("col.*")
        tests = self.__append_partition_data(tests)
        return tests

    def __get_suites_data(self, df):
        results = df.select(explode("results"))
        suites = results.select(explode("col.suites"), "col.uuid")
        suites = suites.withColumnRenamed("col.uuid", "test_execution_id")
        suites = suites.select("col.*", "test_execution_id")
        suites = self.__append_partition_data(suites)

    def parse_json_data(self, df):
        suites = self.__get_suites_data(df)
        tests = self.__get_tests_data(suites)
        suites = suites.drop("tests")
        return suites, tests

    def get_json_data(self, s3_source_file_path):
        self.pwa_name = s3_source_file_path.split("/")[3]
        json_s3_file = (
            spark.read.option("multiLine", True)
            .option("mode", "PERMISSIVE")
            .json(s3_source_file_path)
        )
        return json_s3_file.select("results").alias("results")

    def __parse_object_summaries(self, paths):
        return map(lambda x: f"s3://{x.bucket_name}/{x.key}", paths)

    def build_file_paths(self, bucket):
        s3_source_raw_file_paths = bucket.objects.all()
        s3_source_combined_file_paths = self.__parse_object_summaries(
            s3_source_raw_file_paths
        )
        s3_source_full_file_paths = self.__filter_for_full_file_paths(
            s3_source_combined_file_paths
        )
        s3_source_full_json_paths = self.__filter_for_json_file_paths(
            s3_source_full_file_paths
        )
        s3_source_file_paths = self.__filter_for_execution_date(
            s3_source_full_json_paths
        )
        return s3_source_file_paths

    def build_target_file_path(self, table_name, s3_file_path_target):
        dt = str(self.__parse_execution_date())
        database_location = f"{s3_file_path_target}/{table_name}/pwa={self.pwa_name}/"
        table_name = f"dt={dt}"
        return database_location, table_name
