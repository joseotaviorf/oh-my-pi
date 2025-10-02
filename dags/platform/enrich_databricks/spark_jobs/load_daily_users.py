import json
import pyspark.sql.functions as F
from pyspark.sql import DataFrame
from pyspark.sql.types import StructType, StructField, StringType, BooleanType
from argparse import ArgumentParser, Namespace
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.services import ConfigurationService
from databricks.sdk import AccountClient

JOB_NAME = "load_daily_users"

schema = StructType(
    [
        StructField("id_user", StringType(), True),
        StructField("email", StringType(), True),
        StructField("is_active_user", BooleanType(), True),
    ]
)


def main() -> None:
    args = parse_args()
    config_service = ConfigurationService(args.dag_name)
    account_id = config_service.get_config("account_id")
    df = get_users_df(account_id)
    df = enrich_users_with_employee_information(df)
    load_df(
        df,
        env=args.env,
        database_base_name=args.database_base_name,
        datalake_bucket=args.datalake_bucket,
        table_name=args.table_name,
        partition_by=json.loads(args.partitions),
    )


def parse_args() -> Namespace:
    """Parse arguments passed to the job"""

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod values")
    parser.add_argument("datalake_bucket", type=str, help="datalake bucket")
    parser.add_argument(
        "dag_name",
        type=str,
        help="name of the Airflow DAG, without the bietlejuice prefix",
    )
    parser.add_argument(
        "database_base_name",
        type=str,
        help="base name for database, e.g. 'source' for raw/clean layer and 'source' and/or 'context' for enrich layer",
    )
    parser.add_argument("table_name", type=str, help="table name that will be created")
    parser.add_argument("partitions", help="list with partition cols")

    return parser.parse_args()


def get_users_df(account_id: str) -> DataFrame:
    """Uses the Databricks API to return a dataframe with all current users"""

    account_client = get_account_client(account_id)
    users = []
    for user in account_client.users.list():
        users.append((user.id, user.emails[0].value, user.active))

    # We use current_date because it's a snapshot. We can't process the history, so no point
    # in using the execution date or load_start_date
    df = spark.createDataFrame(users, schema).withColumns(
        {
            "year": F.year(F.current_date()),
            "month": F.month(F.current_date()),
            "day": F.dayofmonth(F.current_date()),
        }
    )

    return df


def get_account_client(account_id: str) -> AccountClient:
    secret = json.loads(
        dbutils.secrets.get(scope="data-ingestion", key="db-credentials-idn")
    )

    return AccountClient(
        host="https://accounts.cloud.databricks.com/",
        client_id=secret["client_id"],
        client_secret=secret["secret"],
        account_id=account_id,
    )


def enrich_users_with_employee_information(users_df) -> DataFrame:
    """
    Adds the column "is_active_employee" to the users dataframe by joining with the org_chart table
    """
    active_employees_df = spark.table("datalake_people_public.org_chart").filter(
        "assignment_status_type = 'ACTIVE'"
    )
    return (
        users_df.join(
            active_employees_df,
            users_df.email == active_employees_df.work_email,
            "left",
        )
        .withColumn("is_active_employee", F.col("work_email").isNotNull())
        .select(
            "id_user",
            "email",
            "is_active_user",
            "is_active_employee",
            "year",
            "month",
            "day",
        )
    )


def load_df(
    users_df: DataFrame,
    env: str,
    database_base_name: str,
    datalake_bucket: str,
    table_name: str,
    partition_by: list[str],
) -> None:
    database_name, database_location, _ = DatalakeMetastoreService.get_layer_info(
        env, database_base_name, datalake_bucket, "enrich"
    )
    s3_path = database_location + table_name
    loader = DeltaLoader(spark)
    loader.load_table(
        table_name=f"{database_name}.{table_name}",
        path=s3_path,
        source_df=users_df,
        partition_by=partition_by,
    )


if __name__ == "__main__":
    main()
