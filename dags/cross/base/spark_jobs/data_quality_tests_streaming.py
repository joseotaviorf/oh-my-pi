import logging

from pyspark.sql.functions import col, from_json
from pyspark.sql.types import StringType, StructField, StructType

from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.pipeline.data_quality_tests_pipeline import DataQualityTestsPipeline
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "data_quality_tests_consumer"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = logging.getLogger(JOB_NAME)
logger.setLevel(logging.INFO)


message_schema = StructType(
    [
        StructField("env", StringType(), False),
        StructField("execution_date", StringType(), False),
        StructField("inmetro_bucket", StringType(), False),
        StructField("layer", StringType(), False),
        StructField("relative_file_path", StringType(), False),
        StructField("table_name", StringType(), False),
        StructField("intermediate_path", StringType(), False),
    ]
)


def run_validation_job(params: dict):
    """
    Runs the data quality tests for a single table
    """
    env = params["env"]
    execution_date = params["execution_date"]
    inmetro_bucket = params["inmetro_bucket"].replace("s3://", "")
    layer = LayerEnum(params["layer"])
    relative_file_path = params["relative_file_path"]
    table_name = params["table_name"]
    intermediate_path = params["intermediate_path"]

    logger.info(
        f"m={JOB_NAME}, env={env}, inmetro_bucket={inmetro_bucket}, layer={layer.value}, "
        f"relative_file_path={relative_file_path}, table_name={table_name},  msg=Job execution started."
    )

    pipeline = DataQualityTestsPipeline(
        env,
        execution_date,
        inmetro_bucket,
        layer,
        relative_file_path,
        table_name,
        intermediate_path,
    )
    pipeline.run()
    logger.info(
        f"m={JOB_NAME}, env={env}, inmetro_bucket={inmetro_bucket}, layer={layer.value}, "
        f"relative_file_path={relative_file_path}, table_name={table_name},  msg=Job execution finished."
    )


def process_batch(df, epoch_id):
    """
    This function is called for each micro-batch of messages from Kafka.
    It collects the messages to the driver and runs the validation job for each one.
    """
    if df.count() > 0:
        messages = df.collect()
        for row in messages:
            params = row.asDict()
            try:
                logger.info(f"Processing message for table: {params['table_name']}")
                run_validation_job(params)
            except Exception as e:
                logger.error(
                    f"Failed to process message: {params}. Error: {e}", exc_info=True
                )


def main() -> None:
    config_service = ConfigurationService()

    datalake_bucket = config_service.get_config("datalake_bucket")
    kafka_broker = dbutils.secrets.get(
        scope="quintoandar", key="DATABRICKS_DATA_QUALITY_BOOTSTRAP"
    )
    kafka_topic = config_service.get_config("data_quality_tests_kafka_topic")
    kafka_api_key = dbutils.secrets.get("quintoandar", "DATABRICKS_DATA_QUALITY_KEY")
    kafka_api_secret = dbutils.secrets.get(
        "quintoandar", "DATABRICKS_DATA_QUALITY_SECRET"
    )

    kafka_options = {
        "kafka.bootstrap.servers": kafka_broker,
        "subscribe": kafka_topic,
        "kafka.security.protocol": "SASL_SSL",
        "kafka.sasl.mechanism": "PLAIN",
        "kafka.sasl.jaas.config": f'org.apache.kafka.common.security.plain.PlainLoginModule required username="{kafka_api_key}" password="{kafka_api_secret}";',
        "startingOffsets": "earliest",
        "failOnDataLoss": "false",
    }

    kafka_stream_df = spark.readStream.format("kafka").options(**kafka_options).load()
    parsed_df = (
        kafka_stream_df.selectExpr("CAST(value AS STRING)")
        .select(from_json(col("value"), message_schema).alias("data"))
        .select("data.*")
    )
    query = (
        parsed_df.writeStream.foreachBatch(process_batch)
        .option("checkpointLocation", f"s3://{datalake_bucket}/checkpoints/{JOB_NAME}")
        .start()
    )
    query.awaitTermination()


if __name__ == "__main__":
    main()
