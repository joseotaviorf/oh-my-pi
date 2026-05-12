import logging
import json
from argparse import ArgumentParser, Namespace

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.base.spark.runtime_detector import RuntimeDetector
from bietlejuice.pipeline.data_quality_tests_pipeline import DataQualityTestsPipeline
from bietlejuice.services.configuration_service import ConfigurationService


JOB_NAME = "data_quality_tests"
logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def parse_args():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="Environment where the task is executing")
    parser.add_argument(
        "execution_date", type=str, help="Execution date when the task is executing"
    )
    parser.add_argument(
        "inmetro_bucket",
        type=str,
        help="Bucket that stores all the Inmetro's validation data",
    )
    parser.add_argument("layer", type=str, help="One of LayerEnum values")
    parser.add_argument(
        "relative_file_path",
        type=str,
        help="The `source` name for clean layer."
        " The `source` and/or `context` name for enrich layer. The `schema` for DW layer.",
    )
    parser.add_argument("table_name", type=str)
    parser.add_argument(
        "intermediate_path",
        type=str,
        nargs="?",
        default="",
        help="partial path used in some DAGs off of our pattern",
    )

    return parser.parse_args()


def can_run_data_quality_in_this_cluster() -> bool:
    """
    Decide whether PyDeequ can run in this driver process.

    - EMR (``SPARK_RUNTIME=emr``): always run in-process; no UC shared restriction.
    - Databricks single-user UC: run in-process.
    - Databricks shared UC: defer to the Kafka consumer on a single-user cluster.
    """
    if RuntimeDetector.is_emr():
        return True
    # PyDeequ is not compatible with Unity Catalog in Shared mode
    return (
        spark.conf.get("spark.databricks.clusterUsageTags.clusterUnityCatalogMode")
        == "SINGLE_USER"
    )


def publish_data_quality_request_to_kafka(args: Namespace) -> None:
    """
    We have a separate job that runs in a single-user cluster (compatible with PyDeequ).
    This function publishes a message to a Kafka topic that that job listens to.

    Uses :class:`BaseDBUtils` so secrets resolve on EMR (AWS Secrets Manager facade)
    and on Databricks (native ``dbutils``).
    """

    dbutils = BaseDBUtils().get_dbutils()
    if dbutils is None:
        raise RuntimeError(
            "dbutils is not available; cannot publish data quality request to Kafka. "
            "On EMR set SPARK_RUNTIME=emr and ensure the EMR secrets facade is configured."
        )

    broker = dbutils.secrets.get(
        scope="quintoandar", key="DATABRICKS_DATA_QUALITY_BOOTSTRAP"
    )
    key = dbutils.secrets.get(scope="quintoandar", key="DATABRICKS_DATA_QUALITY_KEY")
    secret = dbutils.secrets.get(
        scope="quintoandar", key="DATABRICKS_DATA_QUALITY_SECRET"
    )
    config_service = ConfigurationService()
    topic = config_service.get_config("data_quality_tests_kafka_topic")

    try:
        publish_message(
            message=json.dumps(vars(args)),
            topic=topic,
            broker=broker,
            key=key,
            secret=secret,
        )

    except Exception as e:
        logger.error(f"Failed to publish message to Kafka. Error: {e}")
        raise


def publish_message(message: str, topic: str, broker: str, key: str, secret: str) -> None:
    """
    Publishes a message to a Kafka topic using Spark's Kafka integration.

    Yes, it is overkill to use Spark to write a single message. However, the native kafka-python library
    fails due to network issues in Databricks Shared clusters. Spark doesn't have the same limitations.
    """

    df = spark.createDataFrame([(message,)], ["value"])

    jaas_config = (
        f'org.apache.kafka.common.security.plain.PlainLoginModule required '
        f'username="{key}" password="{secret}";'
    )

    logger.info(f"Publishing request to topic '{topic}'...")
    (
        df.write.format("kafka")
        .option("kafka.bootstrap.servers", broker)
        .option("kafka.security.protocol", "SASL_SSL")
        .option("kafka.sasl.mechanism", "PLAIN")
        .option("kafka.sasl.jaas.config", jaas_config)
        .option("topic", topic)
        .save()
    )
    logger.info(f"Successfully published message to topic '{topic}'")


def main() -> None:
    global spark
    if RuntimeDetector.is_emr():
        from bietlejuice.base.spark.spark_session_factory import create_emr_spark_session

        spark = create_emr_spark_session(JOB_NAME)

    args = parse_args()

    if can_run_data_quality_in_this_cluster():
        pipeline = DataQualityTestsPipeline(
            args.env,
            args.execution_date,
            args.inmetro_bucket.replace("s3://", ""),
            LayerEnum(args.layer),
            args.relative_file_path,
            args.table_name,
            args.intermediate_path,
        )
        pipeline.run()
    else:
        logger.warning(
            "This cluster is not compatible with running data quality tests directly. "
            "Publishing request to Kafka instead."
        )
        publish_data_quality_request_to_kafka(args)


if __name__ == "__main__":
    try:
        main()
    finally:
        try:
            if RuntimeDetector.is_emr():
                spark.sparkContext._gateway.shutdown_callback_server()
                spark.stop()
        except NameError:
            pass
