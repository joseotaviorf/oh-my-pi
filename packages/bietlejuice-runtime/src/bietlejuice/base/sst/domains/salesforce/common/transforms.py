import pyspark.sql.functions as F


def filter_relevant_cdc_events(
    df,
    tracked_columns=None,
    event_type_col="event_type",
    changed_fields_col="changed_field",
):
    """
    Filter Salesforce CDC events based on tracked field changes.

    Regular UPDATE events are kept only when at least one field in
    `changed_fields_col` matches a value in `tracked_columns`.

    UPDATE events are also kept when the changed-fields metadata is missing
    or unreliable, including NULL, an empty array, or an array containing an
    empty string. This prevents valid events from being discarded due to
    incomplete upstream metadata.

    Non-UPDATE events are always kept.

    If `tracked_columns` is empty or None, no filtering is applied.

    Args:
        df: Input PySpark DataFrame containing Salesforce CDC events.
        tracked_columns: Fields that should trigger an update when changed.
        event_type_col: Column containing the CDC event type.
        changed_fields_col: Array column containing the changed field names.

    Returns:
        A filtered PySpark DataFrame.
    """
    if not tracked_columns:
        return df

    changed_field = F.col(changed_fields_col)
    # This is just to ensure we're covering incorrect changed_fields in case of any upstream bug

    missing_or_invalid_fields = (
        changed_field.isNull()
        | (F.size(changed_field) == 0)  # No updates
        | F.array_contains(changed_field, "")  #
    )

    tracked_array = F.array(*[F.lit(column) for column in tracked_columns])
    has_relevant_changed_field = F.arrays_overlap(
        changed_field,
        tracked_array,
    )
    is_update = F.col(event_type_col) == "UPDATE"
    return df.filter(
        ~is_update | missing_or_invalid_fields | has_relevant_changed_field
    )
