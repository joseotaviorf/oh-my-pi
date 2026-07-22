import ast
import logging
from argparse import ArgumentParser
from datetime import datetime, timedelta
from functools import reduce

from pyspark.sql.functions import lit, struct, to_json
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkDataFrameService,
    SparkTableStorageFormat,
    spark,
)
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_inmetro_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_dbutils():
    return BaseDBUtils().get_dbutils()


def _generate_date_range(start_date_str, end_date_str):
    start = datetime.strptime(start_date_str, "%Y-%m-%d")
    end = datetime.strptime(end_date_str, "%Y-%m-%d")
    if start > end:
        raise ValueError(
            f"load_start_date ({start_date_str}) must be <= load_end_date ({end_date_str})"
        )
    days = (end - start).days
    return [(start + timedelta(days=i)).strftime("%Y-%m-%d") for i in range(days + 1)]


def _build_inmetro_glob_path(inmetro_bucket, target_date):
    """Shape: {bucket}/{repo}/{database}/{table}/{bucket_directory}/{date}."""
    return f"{inmetro_bucket}/*/*/*/{bucket_directory}/{target_date}"


def _normalize_s3_uri(uri):
    """Normalize s3a:// → s3:// so config URIs match Hadoop FileStatus paths."""
    uri = uri.rstrip("/")
    if uri.startswith("s3a://"):
        return "s3://" + uri[len("s3a://") :]
    return uri


def _glob_status(glob_path):
    """Returns Hadoop FileStatus matches for glob_path as a Python list."""
    sc = spark.sparkContext
    hadoop_path = sc._jvm.org.apache.hadoop.fs.Path(glob_path)
    file_system = hadoop_path.getFileSystem(sc._jsc.hadoopConfiguration())
    statuses = file_system.globStatus(hadoop_path)
    return list(statuses) if statuses is not None else []


def _path_has_objects(glob_path):
    """Checks S3 object existence via Hadoop FileSystem globStatus — no data is read."""
    # Keep existence checks on the JVM array (len) — do not materialize via list().
    sc = spark.sparkContext
    hadoop_path = sc._jvm.org.apache.hadoop.fs.Path(glob_path)
    file_system = hadoop_path.getFileSystem(sc._jsc.hadoopConfiguration())
    statuses = file_system.globStatus(hadoop_path)
    return statuses is not None and len(statuses) > 0


def _parse_inmetro_date_prefix(path, inmetro_bucket, target_date):
    """Parse {bucket}/{repo}/{database}/{table}/{bucket_directory}/{date}[/...] .

    Pure Python path parsing — no Spark Analyzer / function-name resolution.
    Returns (repo, database, table) or None if the path does not match.
    """
    path = _normalize_s3_uri(path)
    bucket = _normalize_s3_uri(inmetro_bucket)
    prefix = bucket + "/"
    if not path.startswith(prefix):
        return None

    parts = path[len(prefix) :].split("/")
    if len(parts) < 5:
        return None

    repo, database, table, directory, date_part = parts[:5]
    if directory != bucket_directory or date_part != target_date:
        return None

    return repo, database, table


def _list_inmetro_date_prefixes(inmetro_bucket, target_date):
    """Enumerate distinct producer date-prefixes via Hadoop globStatus.

    Returns a list of (repo, database, table, prefix_path) tuples. prefix_path is
    the exact directory spark.read should load for that producer.
    """
    # Match objects under the date dir (/*), same shape as the existence check.
    statuses = _glob_status(
        f"{_build_inmetro_glob_path(inmetro_bucket, target_date)}/*"
    )
    bucket = _normalize_s3_uri(inmetro_bucket)
    results = []
    seen = set()

    for status in statuses:
        path_str = status.getPath().toString()
        parsed = _parse_inmetro_date_prefix(path_str, inmetro_bucket, target_date)
        if parsed is None or parsed in seen:
            continue
        seen.add(parsed)
        repo, database, table = parsed
        prefix_path = (
            f"{bucket}/{repo}/{database}/{table}/{bucket_directory}/{target_date}"
        )
        results.append((repo, database, table, prefix_path))

    return results


def _load_single_prefix(
    prefix_path, repo, database, table, serialize_columns_from_directory
):
    """Read one producer prefix and attach path metadata via Literal columns only."""
    df = spark.read.format("json").load(prefix_path)

    if serialize_columns_from_directory:
        df = df.withColumn(
            "inmetro_info", to_json(struct([df[x] for x in df.columns]))
        ).select("inmetro_info")

    return (
        df.withColumn("repo", lit(repo))
        .withColumn("database", lit(database))
        .withColumn("table", lit(table))
    )


def _load_single_date(
    target_date, serialize_columns_from_directory, partition_cols, inmetro_bucket
):
    prefixes = _list_inmetro_date_prefixes(inmetro_bucket, target_date)
    if not prefixes:
        raise RuntimeError(
            f"No parseable producer prefixes under "
            f"{_build_inmetro_glob_path(inmetro_bucket, target_date)}"
        )

    prefix_dfs = [
        _load_single_prefix(
            prefix_path, repo, database, table, serialize_columns_from_directory
        )
        for repo, database, table, prefix_path in prefixes
    ]
    # Producer suites may differ in nested JSON shape; union by name with
    # missing columns as null — intended to match single-glob JSON read.
    df = reduce(lambda a, b: a.unionByName(b, allowMissingColumns=True), prefix_dfs)

    df = (
        SparkDataFrameService()
        .input(df)
        .create_year_month_day_columns_from_date(
            datetime.strptime(target_date, "%Y-%m-%d")
        )
        .optimize_partitions_by_partition_columns(partition_cols)
        .output()
    )

    return df


def get_inmetro_data(
    serialize_columns_from_directory, partition_cols, load_start_date, load_end_date
):
    dates = _generate_date_range(load_start_date, load_end_date)
    logger.info(f"m={JOB_NAME}, dates={dates}, msg=Loading date range")

    config_service = ConfigurationService(source)
    inmetro_bucket = config_service.get_config("inmetro_bucket")

    dfs = []
    loaded, skipped_no_data, errored = [], [], []
    for target_date in dates:
        glob_path = _build_inmetro_glob_path(inmetro_bucket, target_date)

        # Check inside the date dir (/*) so an empty dir counts as "no data" and doesn't fail spark.read.
        try:
            path_has_objects = _path_has_objects(f"{glob_path}/*")
        except Exception as e:
            errored.append(target_date)
            logger.error(
                f"m={JOB_NAME}, date={target_date}, path={glob_path}, "
                f"msg=Path existence check failed, error={e}",
                exc_info=True,
            )
            continue

        if not path_has_objects:
            skipped_no_data.append(target_date)
            logger.info(
                f"m={JOB_NAME}, date={target_date}, path={glob_path}, "
                "msg=No objects at path, skipping date"
            )
            continue

        try:
            df = _load_single_date(
                target_date,
                serialize_columns_from_directory,
                partition_cols,
                inmetro_bucket,
            )
        except Exception as e:
            errored.append(target_date)
            logger.error(
                f"m={JOB_NAME}, date={target_date}, path={glob_path}, "
                f"msg=Read failed although objects exist at path, error={e}",
                exc_info=True,
            )
            continue

        dfs.append(df)
        loaded.append(target_date)
        logger.info(f"m={JOB_NAME}, date={target_date}, msg=Loaded successfully")

    summary_log = logger.warning if errored else logger.info
    summary_log(
        f"m={JOB_NAME}, requested={dates}, loaded={loaded}, "
        f"skipped_no_data={skipped_no_data}, errored={errored}, "
        "msg=Date range ingestion summary"
    )

    if not dfs:
        return None

    return reduce(lambda a, b: a.unionByName(b), dfs)


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name")
    parser.add_argument("execution_date")
    parser.add_argument("partition_cols")
    parser.add_argument("bucket_directory")
    parser.add_argument("serialize_columns_from_directory")
    parser.add_argument("load_end_date", nargs="?", default=None)
    add_validation_target_args(parser)
    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    execution_date = args.execution_date
    partition_cols = ast.literal_eval(args.partition_cols)
    bucket_directory = args.bucket_directory
    serialize_columns_from_directory = ast.literal_eval(
        args.serialize_columns_from_directory
    )
    load_end_date = args.load_end_date or execution_date

    logger.info(
        f"""
        m={JOB_NAME}, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
        table_name={table_name}, bucket_directory={bucket_directory}, partition_cols={partition_cols},
        load_start_date={execution_date}, load_end_date={load_end_date}, msg=Starting spark job...
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    s3_loader = S3Loader()
    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, source, datalake_bucket
    )

    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = datalake_info["db_raw_path"]
    database_name = datalake_info["db_raw_databricks"]
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=database_name,
            prod_table=table_name,
            prod_location=database_location,
            bucket=datalake_bucket,
            target_database=args.target_database_name,
            target_table=args.target_table_name,
        )
    )

    df = get_inmetro_data(
        serialize_columns_from_directory, partition_cols, execution_date, load_end_date
    )

    if not df:
        logger.warning(
            f"m={JOB_NAME}, msg=There is no data currently available in the {bucket_directory} directory"
        )
    else:
        spark_metastore_service.create_database(write_database_name)

        s3_loader.load_df(
            df=df,
            s3_path=f"{write_location}{write_table_name}",
            format_options=format_options,
            partitions=partition_cols,
        )

        spark_metastore_loader.update_metastore(
            df=df,
            database_name=write_database_name,
            table_name=write_table_name,
            format_options=format_options,
            database_location=write_location,
            partitions=partition_cols,
            force_recreate=False,
        )

        spark_metastore_service.create_new_partitions_from_df(
            df=df,
            database_name=write_database_name,
            table_name=write_table_name,
            partition_cols=partition_cols,
        )

        spark_metastore_service.refresh_table(write_database_name, write_table_name)
