import logging
from argparse import ArgumentParser
from bietlejuice.base.spark import SparkTableStorageFormat

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

from pyspark.sql.functions import col, collect_set

# Link to graphframes lib: https://spark-packages.org/package/graphframes/graphframes
from graphframes import *

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "user_merge_predecessor_list"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

def get_df_user_merge():
  # Creating df from user_merge table and selecting id_loser_account and id_winner_account
  user_merge_df = spark.table("datalake_ebdb_clean.user_merge")
  user_merge_df = user_merge_df.filter(col("status") == 'MERGED')
  user_merge_df = user_merge_df.select(col("id_loser_account"), col("id_winner_account"))

  # Creating edge and vertice dfs to use on GraphFrame
  edge = user_merge_df.withColumnRenamed("id_loser_account", "src").withColumnRenamed("id_winner_account", "dst")

  vertice = user_merge_df.withColumnRenamed("id_winner_account", "id")
  vertice = vertice.drop(col("id_loser_account"))
  vertice = vertice.union(user_merge_df.select(col("id_loser_account")))

  g = GraphFrame(vertice, edge)

  # Creating a df using connectedComponents() method , it creates a column (component) with the lowest vertice value that is common with all the connected vertices.
  # [https://graphframes.github.io/graphframes/docs/_site/api/python/graphframes.html#graphframes.GraphFrame.connectedComponents]
  sc.setCheckpointDir("/tmp/connectedComponents")
  user_components = g.connectedComponents()

  # Creating df from user table
  user_df = spark.table("datalake_ebdb_clean.user")

  # Renaming columns to facilitate the select below
  user_merge = user_components.withColumnRenamed("id", "id_user").withColumnRenamed("component", "id_component")

  # Joining user with user_merge dfs comparing the id_user and selecting the columns that interest for us
  components = user_df.join(user_merge, (user_df.id == user_merge.id_user), "inner")
  components = components.select(col("id"), col("id_component"))
  components = components.withColumnRenamed("id_component", "component")

  # Creating the final df join with user_merge df using the component to get all the predecessor users from datalake_ebdb_clean.user table
  df = components.join(user_merge, (components.component == user_merge.id_component) & (components.id != user_merge.id_user), "inner")

  # Collecting the users with collect_set function and renaming the column to 'predecessor_user_list'
  df = df.groupBy(col("id")).agg(collect_set(col("id_user")).alias("predecessor_user_list"))

  country_user_df = spark.table("datalake_ebdb_country.user")
  df = df.join(country_user_df, country_user_df.id_user == df.id, "left")
  df = df.select(col("id"), col("country_code"), col("predecessor_user_list"))
  df = df.withColumnRenamed("id", "id_user")

  return df

if __name__ == "__main__":
  parser = ArgumentParser(description=JOB_NAME)

  parser.add_argument("environment", help="forno/prod values")
  parser.add_argument("datalake_bucket", help="datalake_bucket")
  parser.add_argument("dag_name", help="dag_name")
  parser.add_argument("table_name", help="table_name")
  parser.add_argument("context", help="context")
  
  args = parser.parse_args()

  environment = args.environment
  datalake_bucket = args.datalake_bucket
  dag_name = args.dag_name
  table_name = args.table_name
  context = args.context

  logger.info(
        f"""m=__main__, environment={environment},
        datalake_bucket={datalake_bucket}, dag_name={dag_name}, 
        table_name={table_name}, context={context}
        msg=User Merge spark job running.
        """
  )

  spark_client = SparkClient()

  s3_loader = S3Loader()
  spark_metastore_service = SparkMetastoreService(spark_client)
  spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

  db_info = DatalakeMetastoreService.get_db_info(environment, context, datalake_bucket)
  database_name = db_info["db_enrich_databricks"]
  database_location = db_info["db_enrich_path"]
  spark_metastore_service.create_database(database_name)

  df = get_df_user_merge()

  if df:
    s3_loader.load_df(
      df=df,
      format_options=SparkTableStorageFormat.DEFAULT_ENRICH,
      s3_path=f"{database_location}{table_name}",
    )

    spark_metastore_loader.update_metastore(
      df=df,
      database_name=database_name,
      table_name=table_name,
      format_options=SparkTableStorageFormat.DEFAULT_ENRICH,
      database_location=database_location,
    )
  else:
    logger.error(
        f"""msg=Error while getting data for user_merge table.
        The Dataframe is empty!
        """
  )