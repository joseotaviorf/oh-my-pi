from pyspark.sql import DataFrame
import pyspark.sql.functions as F


def sf_cdc_mandatory_fields(df: DataFrame) -> DataFrame:
    """
    Break down ChangeEventHeader from SF CDC into multiple columns and do a mandatory id check
    Return a DF with all new columns in ChangeEventHeader
    """

    cols = df.columns
    assert "ChangeEventHeader" in cols, "Missing CDC column"

    sf_cols = {
        "record_id": F.explode(F.col("ChangeEventHeader.recordIds")),
        "entity_name": F.col("ChangeEventHeader.entityName"),
        "event_type": F.col("ChangeEventHeader.changeType"),
        "transaction_key": F.col("ChangeEventHeader.transactionKey"),
        "sequence_number": F.col("ChangeEventHeader.sequenceNumber"),
        "commit_number": F.col("ChangeEventHeader.commitNumber"),
        "commit_ts": F.col("ChangeEventHeader.commitTimestamp"),
        "commit_user": F.col("ChangeEventHeader.commitUser"),
        "changed_field": F.col("ChangeEventHeader.changedFields"),
    }

    # Apply all expressions above and all columns from previous state
    return df.select(*[expr.alias(name) for name, expr in sf_cols.items()], *cols)
