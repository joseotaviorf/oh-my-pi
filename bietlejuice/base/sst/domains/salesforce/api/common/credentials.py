from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.spark.base_spark import BaseDBUtils
import json


# This is databricks specific, we can keep it at common
def retrieve_credentials(api_enum: APIEnum, scope="quintoandar"):
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()
    return json.loads(dbutils.secrets.get(scope=scope, key=api_enum))
