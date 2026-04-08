import pyspark.sql.functions as F


def nullify_fields_on_delete(df, non_null_cols=None):
    """
    Set columns to NULL on rows where event_type == "DELETE", except columns listed in
    non_null_cols (metadata / keys kept for lineage).
    """
    if non_null_cols is None:
        non_null_cols = []

    null_cols = set(df.columns) - set(non_null_cols)
    return df.select(
        *[
            (
                F.when(F.col("event_type") == "DELETE", F.lit(None))
                .otherwise(F.col(col))
                .alias(col)
                if col in null_cols
                else F.col(col)
            )
            for col in df.columns  # So we don't change column order
        ]
    )
