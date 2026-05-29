import pyspark.sql.functions as F
from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("sst.domains.salesforce.clean.checks")


def check_for_create_partition(df):
    """
    Validate CREATE event presence per record_id within the current CDC partition.

    This function aggregates the incoming CDC dataframe (typically a daily/hourly
    partition) and verifies whether each `record_id` contains at least one
    CREATE event.

    Context:
        When building a CDC-based table, every logical entity must originate
        from a CREATE event. However, in incremental (daily/hourly) partitions,
        we may receive only UPDATE/DELETE events for records that were
        originally created in previous partitions.

    Behavior:
        - Groups by `record_id`
        - Checks if at least one event_type == "CREATE" exists
        - Returns a dataframe with:
            record_id
            has_create (boolean)

    Downstream usage:
        - If `has_create` is False, we must validate whether the record
          already exists in historical data.
        - If the record does not exist historically, it should either:
            • Fail the pipeline, or
            • Be routed to a dead-letter queue for further inspection.

    Parameters
    ----------
    df : pyspark.sql.DataFrame
        CDC dataframe containing at minimum `record_id` and `event_type`.

    Returns
    -------
    pyspark.sql.DataFrame
        Aggregated dataframe with one row per record_id and a boolean
        flag indicating CREATE presence.
    """
    return df.groupby("id_record").agg(
        F.bool_or(F.col("event_type").isin("CREATE", "RECOVERY")).alias("has_create")
    )
