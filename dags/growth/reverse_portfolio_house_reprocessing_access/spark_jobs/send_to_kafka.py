import json
import base64
from argparse import ArgumentParser
from datetime import datetime, timedelta
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, struct, to_json, lit
from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "send_historical_houses_to_kafka"

logger = QuintoAndarLogger(JOB_NAME)

spark = SparkSession.builder.appName(JOB_NAME).getOrCreate()

def get_kafka_credentials(dbutils):
    """Get and decode Kafka credentials from Databricks secrets."""
    try:
        spark_token = dbutils.secrets.get(scope="quintoandar", key="RENEDESCARTES_SA_CONFLUENT")
        raw_credentials = json.loads(spark_token)
        str_credentials = raw_credentials.get("pwd")
        
        if not str_credentials:
            raise ValueError("Missing 'pwd' field in credentials")
        
        decoded_credentials = base64.b64decode(str_credentials).decode("utf-8")
        credentials = dict(line.split("=", 1) for line in decoded_credentials.strip().splitlines())
        
        kafka_api_key = credentials.get("KEY")
        kafka_api_secret = credentials.get("VALUE")
        
        if not kafka_api_key or not kafka_api_secret:
            raise ValueError("Missing KEY or VALUE in decoded credentials")
        
        return kafka_api_key, kafka_api_secret
        
    except Exception as e:
        logger.error(f"Failed to get Kafka credentials: {str(e)}")
        raise


def send_data_to_kafka(df, kafka_key_column, kafka_topic, kafka_api_key, kafka_api_secret, kafka_bootstrap_servers):
    """Send DataFrame to Kafka topic."""
    try:
        row_count = df.count()
        
        if row_count == 0:
            print("No data to send")
            return
        
        payload_cols = [c for c in df.columns if c not in ["_change_type", "_commit_version", "_commit_timestamp"]]

        df_send = (
            df.select(
                col(kafka_key_column).cast("string").alias("key"),
                to_json(
                    struct(
                        struct(*[col(c) for c in payload_cols]).alias("payload"),
                        col("_change_type"),
                        col("_commit_timestamp")
                    )
                ).alias("value")
            )
        )
        
        (
            df_send.write
            .format("kafka")
            .option("kafka.bootstrap.servers", kafka_bootstrap_servers)
            .option("topic", kafka_topic)
            .option("kafka.security.protocol", "SASL_SSL")
            .option("kafka.sasl.mechanism", "PLAIN")
            .option(
                "kafka.sasl.jaas.config",
                f'kafkashaded.org.apache.kafka.common.security.plain.PlainLoginModule required username="{kafka_api_key}" password="{kafka_api_secret}";'
            )
            .save()
        )
        
        print(f"Sent {row_count} records to Kafka")
        
    except Exception as e:
        logger.error(f"Failed to send data to Kafka: {str(e)}")
        raise

def process_date_range(source_table, start_date, end_date, kafka_key_column, kafka_topic, kafka_api_key, kafka_api_secret, kafka_bootstrap_servers):
    """Process data for the specified date range and send to Kafka."""
    print(f"Processing date range: {start_date} to {end_date}")
    
    total_days = (end_date - start_date).days
    if total_days <= 0:
        print("No days to process")
        return
    
    total_records_sent = 0
    days_processed = 0
    days_skipped = 0
    df_full = None
    
    try:
        print("Reading table with full date range filter...")
        start_date_str = start_date.isoformat()
        end_date_str = end_date.isoformat()
        
        df_full = spark.read.format("delta").table(source_table)
        
        created_at_type = dict(df_full.dtypes)["createdAt"]
        if "timestamp" in created_at_type.lower():
            from pyspark.sql.functions import to_date
            df_full = df_full.filter(
                (to_date(col("createdAt")) >= lit(start_date_str)) &
                (to_date(col("createdAt")) < lit(end_date_str))
            )
        else:
            df_full = df_full.filter(
                (col("createdAt") >= lit(start_date_str)) &
                (col("createdAt") < lit(end_date_str))
            )
        
        df_full = (df_full
            .withColumn("_change_type", lit("insert"))
            .withColumn("_commit_timestamp", col("createdAt"))
        )
        
        df_full.cache()
        
        total_records_in_range = df_full.count()
        print(f"Total records in date range: {total_records_in_range}")
        
        if total_records_in_range == 0:
            print("No data in the specified date range")
            return
        
        current_date = start_date
        while current_date < end_date:
            next_day = current_date + timedelta(days=1)
            
            try:
                current_date_str = current_date.isoformat()
                next_day_str = next_day.isoformat()
                
                if "timestamp" in created_at_type.lower():
                    from pyspark.sql.functions import to_date
                    df_day = df_full.filter(
                        (to_date(col("createdAt")) >= lit(current_date_str)) &
                        (to_date(col("createdAt")) < lit(next_day_str))
                    )
                else:
                    df_day = df_full.filter(
                        (col("createdAt") >= lit(current_date_str)) &
                        (col("createdAt") < lit(next_day_str))
                    )

                row_count = df_day.count()

                if row_count == 0:
                    days_skipped += 1
                    current_date = next_day
                    continue

                send_data_to_kafka(df_day, kafka_key_column, kafka_topic, kafka_api_key, kafka_api_secret, kafka_bootstrap_servers)
                
                total_records_sent += row_count
                days_processed += 1
                print(f"Processed {current_date}: {row_count} records")
                
            except Exception as e:
                logger.error(f"Error processing date {current_date}: {str(e)}")
                days_skipped += 1
            
            current_date = next_day

    except Exception as e:
        logger.error(f"Critical error in date range processing: {str(e)}")
        raise
    
    finally:
        if df_full is not None:
            try:
                df_full.unpersist()
            except:
                pass
        
        print(f"Summary - Days processed: {days_processed}, Records sent: {total_records_sent}")

if __name__ == "__main__":
    print(f"Starting job: {JOB_NAME}")
    
    try:
        parser = ArgumentParser(description=JOB_NAME)
        parser.add_argument("load_start_date", help="The beginning date to process. Format: YYYY-MM-DD")
        parser.add_argument("load_end_date", help="The end date to process. Format: YYYY-MM-DD")
        parser.add_argument("environment", help="The environment to process. Format: forno, prod")

        arguments = parser.parse_args()

        try:
            start_date = datetime.strptime(arguments.load_start_date, "%Y-%m-%d").date()
            end_date = datetime.strptime(arguments.load_end_date, "%Y-%m-%d").date()
            
            if start_date >= end_date:
                raise ValueError(f"Start date ({start_date}) must be before end date ({end_date})")
                
        except ValueError as e:
            logger.error(f"Date parsing/validation error: {str(e)}")
            raise

        config_service = ConfigurationService("reverse_portfolio_house_reprocessing_access")
        topic_sufix = config_service.get_config("topic_sufix")
        kafka_key_column = "propertyId"
        kafka_topic = f"{arguments.environment}_renedescartes.{topic_sufix}"
        
        kafka_config = config_service.get_config("kafka")
        kafka_bootstrap_servers = kafka_config["bootstrap_servers"]

        base_dbutils = BaseDBUtils()
        dbutils = base_dbutils.get_dbutils()
        
        if dbutils is None:
            raise RuntimeError("Failed to initialize Databricks utilities")
        
        kafka_api_key, kafka_api_secret = get_kafka_credentials(dbutils)
        
        table_name = config_service.get_config("table_name")
        full_table_name = f"quintoandar_{arguments.environment}.reverse_house_portfolio_reprocessing.{table_name}"
        
 
        process_date_range(
            full_table_name,
            start_date,
            end_date,
            kafka_key_column,
            kafka_topic,
            kafka_api_key,
            kafka_api_secret,
            kafka_bootstrap_servers
        )
        
        print("Job completed successfully")
        
    except Exception as e:
        logger.error(f"Job failed: {str(e)}")
        raise