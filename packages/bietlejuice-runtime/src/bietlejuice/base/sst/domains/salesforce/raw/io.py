from pyspark.sql import DataFrame, SparkSession


def read_sf_cdc_json(spark: SparkSession, file_path: str) -> DataFrame:
    """
    Default json reader for SF events from CDC pipelines via APPFlow

    """
    return (
        spark.read.option("recursiveFileLookup", "true")
        .option("multiLine", "false")  # important
        .option("mode", "PERMISSIVE")
        .option("columnNameOfCorruptRecord", "_corrupt_record")
        .json(file_path)
    )
