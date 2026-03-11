from quintoandar_logger import QuintoAndarLogger
import pyspark.sql.functions as F

logger = QuintoAndarLogger("sst.domains.salesforce.clean.checks")


@logger(exclude=["df"], exclude_return=False)
def check_missing_create(df, fail=True):
    """
    Considering we're using CDC events, we would need a previous state to create new state while we have UPDATE/DELETE rows
    This checks if we have a previous state for each record_id. If not, we'll fail the job or send it to a dead queue
    """
    rows_count = (
        df.where(F.col("event_type") == "HISTORICAL")
        .where(F.col("commit_number").isNull())
        .count()
    )
    if rows_count > 0:
        logger.info(
            f"m=check_missing_create, msg= Missing create event for {rows_count} records"
        )
        if fail:
            raise ValueError(f"Missing initial state for {rows_count} unique ids")
        else:
            logger.warning(
                f"m=check_missing_create, msg={fail=}\t Historical missing. Ignoring issue"
            )
            return False
    logger.info("m=check_missing_create, msg= No missing create events")
    return True


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
    return df.groupby("record_id").agg(
        F.bool_or(F.col("event_type") == "CREATE").alias("has_create")
    )
