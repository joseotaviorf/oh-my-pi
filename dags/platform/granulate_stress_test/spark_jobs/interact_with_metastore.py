"""
This Spark job will simply try to access a table on the Metastore.
This is here for the stress test, because every so often clusters with Granulate used to start without access to the Metastore.
"""

from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("interact_with_metastore")
table = spark.table("datalake_date.workday_window")
count = table.count()

logger.info(
    f"Interaction with metastore successful. Counted {count} rows in the table."
)
