from argparse import ArgumentParser
from datetime import datetime, timedelta
from quintoandar_logger import QuintoAndarLogger

JOB_NAME = "load_reverse_atento"

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment")
    parser.add_argument("bucket")
    parser.add_argument("dag_name")
    parser.add_argument("schema")
    parser.add_argument("table_name")
    parser.add_argument("load_start_date")
    parser.add_argument("load_end_date")
    parser.add_argument("partner_name")
    parser.add_argument("organization_filters")
    
    args = parser.parse_args()

    environment = args.environment
    bucket = args.bucket
    dag_name = args.dag_name
    schema = args.schema
    table_name = args.table_name
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date
    partner_name = args.partner_name    
    organization_filters = args.organization_filters

    logger = QuintoAndarLogger(f"{dag_name}")

    # Parse ISO format datetime (supports both date-only and full datetime formats) removing the timezone information
    if 'T' in load_start_date:
        load_start_date = datetime.fromisoformat(load_start_date.replace('+00:00', ''))
    else:
        load_start_date = datetime.strptime(load_start_date, "%Y-%m-%d")
    
    if 'T' in load_end_date:
        load_end_date = datetime.fromisoformat(load_end_date.replace('+00:00', ''))
    else:
        load_end_date = datetime.strptime(load_end_date, "%Y-%m-%d")
    
    # Generate date range
    current_date = load_start_date
    date_range = []
    while current_date <= load_end_date:
        date_range.append(current_date)
        current_date += timedelta(days=1)

    logger.info(
        f"m={JOB_NAME}, source={dag_name}, table_name={table_name}, schema={schema}, "
        f"bucket={bucket}, load_start_date={load_start_date.strftime('%Y-%m-%d')}, "
        f"load_end_date={load_end_date.strftime('%Y-%m-%d')}, "
        f"total_dates={len(date_range)}"
    )

    # Execute process for each date in the range
    for execution_date in date_range:
        execution_date_str = execution_date.strftime("%Y-%m-%d")

        logger.info(
            f"m={JOB_NAME}, source={dag_name}, table_name={table_name}, schema={schema}, "
            f"bucket={bucket}, execution_date={execution_date_str}, "
            f"Starting spark job..."
        )

        try:
            logger.info(f"m=Building dataframe from {schema}.{table_name}, execution_date={execution_date_str}...")
            df = spark.sql(f"""
                SELECT 
                    * except (ts_load),
                    ts_load as execution_date
                FROM {schema}.{table_name}
                WHERE DATE(ts_load) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
            """)
            
            # Check if any organization column exists and apply filter
            organization_column = None
            for col in df.columns:
                if "organization" in col.lower():
                    organization_column = col
                    break
            
            if organization_column:
                logger.info(f"m=Filtering by organization, column={organization_column}, organization_filters={organization_filters}")
                df = df.filter(f"{organization_column} IN {organization_filters}")
                logger.info("m=Filter applied successfully")
            
            if df.isEmpty():
                logger.info(f"m=Empty {schema}.{table_name} for execution_date={execution_date_str}!")
            else:
                # Extract year, month, day for partitioned path
                year = execution_date.strftime("%Y")
                month = execution_date.strftime("%m")
                day = execution_date.strftime("%d")
                
                # Create partitioned S3 path
                s3_path = f"s3a://{bucket}/{partner_name.lower()}/{table_name}/year={year}/month={month}/day={day}/"
                file_name = f"{table_name}_{year}_{month}_{day}.csv"
                
                try:
                    logger.info(f"m=Loading Dataframe into s3, s3_path={s3_path}")
                    df.coalesce(1).write.mode("overwrite").option("header", True).csv(s3_path)
                    logger.info(f"m=Dataframe succesfully loaded, s3_path={s3_path}")
                    
                    # Rename the part file to the desired file name
                    logger.info(f"m=Renaming S3 file, s3_path={s3_path}")
                    files = dbutils.fs.ls(s3_path)
                    for f in files:
                        if f.name.startswith("part-") and f.name.endswith(".csv"):
                            source_path = f.path
                            destination_path = f"{s3_path}{file_name}"
                            dbutils.fs.cp(source_path, destination_path)
                            dbutils.fs.rm(source_path)
                            logger.info(
                                f"m=Successfully renamed S3 file to {file_name}, s3_path={destination_path}"
                            )
                            break
                except Exception as e:
                    logger.error(
                        f"m={JOB_NAME}, execution_date={execution_date_str}, "
                        f"Error writing data to S3, s3_path={s3_path}, error={str(e)}"
                    )
                    raise
            
            logger.info(f"m={JOB_NAME}, execution_date={execution_date_str} completed successfully")
        
        except Exception as e:
            logger.error(
                f"m={JOB_NAME}, execution_date={execution_date_str}, "
                f"Error processing data, error={str(e)}"
            )
            raise
    
    logger.info(f"m={JOB_NAME}, All dates processed successfully, total_dates={len(date_range)}")
