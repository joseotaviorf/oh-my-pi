from argparse import ArgumentParser
from datetime import datetime
from quintoandar_logger import QuintoAndarLogger


JOB_NAME = "load_reverse_kyc"

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    logger = QuintoAndarLogger("reverse_kyc")

    parser.add_argument("dag_name")
    parser.add_argument("table_name")
    parser.add_argument("schema")
    parser.add_argument("execution_date")
    parser.add_argument("bucket")
    args = parser.parse_args()

    dag_name = args.dag_name
    table_name = args.table_name
    schema = args.schema
    execution_date = args.execution_date
    bucket = args.bucket

    execution_date = datetime.strptime(execution_date, "%Y-%m-%d")
    s3_path = f"s3a://{bucket}/reverse/{table_name}/"

    logger.info(
        f"""m={JOB_NAME}, source={dag_name}, table_name={table_name}, schema={schema}
        bucket={bucket}, execution_date={execution_date} 
        Starting spark job..."""
    )

    logger.info("m=Building dataframe from reverse layer...")
    df = spark.table(f"reverse_kyc_bigdatacorp.{table_name}")
    if df.isEmpty():
        logger.info("m=Empty Dataframe!")
    else:
        logger.info(f"m=Loading Dataframe into s3, s3_path={s3_path}")
        df.coalesce(1).write.mode("overwrite").option("header", True).csv(s3_path)
        logger.info(f"m=Dataframe succesfully loaded, s3_path={s3_path}")

        logger.info(f"m=Renaming S3 file, s3_path={s3_path}")
        files = dbutils.fs.ls(s3_path)
        for f in files:
            if f.name.startswith("part-") and f.name.endswith(".csv"):
                source_path = f.path
                dbutils.fs.cp(source_path, f"{s3_path}{table_name}.csv")
                dbutils.fs.rm(source_path)
                logger.info(
                    f"m=Sucessfully renamed S3 file, s3_path={s3_path}{table_name}.csv"
                )
