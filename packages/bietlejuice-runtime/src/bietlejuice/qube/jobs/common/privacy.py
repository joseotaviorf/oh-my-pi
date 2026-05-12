from pyspark.sql import Column
from pyspark.sql import functions as F


def redact_value(col: Column, dtype: str) -> Column:
    """
    Returns the redacted value for a column based on its type.
    """
    if dtype == "string":
        return F.lit("___REDACTED___")
    elif dtype == "number":
        return F.lit(-2147483648)  # Sentinel
    elif dtype == "boolean":
        return F.lit(None).cast("boolean")
    return F.lit(None)


def apply_k_anonymity(df, dimension_cols, measure_cols, k: int = 1):
    """
    Given a dataframe with dimension columns and measure counts,
    checks if counts are < k.

    Since we aggregate by dimensions, we need to check the count for that group.
    But wait, the logic in prompt 5.2 says:
    "For each output row (slice), for each counter: If the measure’s count < k, then: Redact dimension values"

    This implies we might have multiple counters. If *any* counter that we care about is < k, do we redact?
    Or is it per counter?

    "If the measure’s count ... < k, then: Redact dimension values ... Option: set counter to 0, or keep it but dimension redaction hides the segment"

    If we have multiple measures in one row, and one is safe but another is unsafe, redacting the dimensions hides the *entire* row's identity, which protects the unsafe one.

    Actually, usually k-anonymity applies to the *set* of quasi-identifiers (dimensions).
    The count of distinct entities in that group must be >= k.

    In 5.2: "Group by date + all dimension columns. ... For each measure m: Compute COUNT ... Output as measure_..._counter"

    So we have a row: [dim1, dim2, count_m1, count_m2].
    If count_m1 < k, we must redact dim1, dim2 for *that* measure's context?
    But the row is shared.

    If we redact dimensions, we essentially merge this small group into a "REDACTED" bucket?
    Or do we just mask the values in output?

    "Redact dimension values: Strings -> RECDACTED..."

    If we just change the values in the row, we are effectively creating a row with "REDACTED", "REDACTED".
    If there are multiple such rows, they might appear as duplicates unless we re-aggregate.
    The prompt does NOT explicitly say re-aggregate. It just says "Write output ... Schema: date, all dimension columns (possibly redacted), and all counter columns."

    So simpler interpretation: Just replace the values in place.

    However, if we have multiple counters, say `visits=100` (safe) and `contracts=2` (unsafe).
    If we redact because of contracts, we hide the segment for visits too?
    The prompt says: "For each output row ... for each counter: If ... < k, then: Redact ..."
    This implies strict logic: if ANY counter violates k-anonymity, the dimensions should be redacted?
    OR, maybe it implies we check k-anonymity per measure?
    But the dimensions are shared keys.

    Let's assume: If *any* exposed count in the row is < k (and > 0, usually), we redact the dimensions.
    Actually, usually metrics are independent.
    But since we output one wide table, we must protect the most sensitive part.

    Let's follow the prompt literally:
    "For each output row (slice), for each counter: If the measure’s count ... < k, then: Redact dimension values"

    This implies an iterative check. If count_A < k -> redact. If count_B < k -> redact.
    So if ANY count is unsafe, we redact.
    """

    # Logic:
    # Create a condition "is_unsafe" = (count_m1 < k) | (count_m2 < k) ...
    # Note: count 0 is usually safe (no one there), but sometimes 0 < k is treated as unsafe?
    # Usually 0 is safe because no one is exposed. k-anonymity is about "not singling out individuals".
    # If count = 0, no individuals are there.
    # If count = 1, 2.. k-1, they are at risk.
    # So condition: (count > 0) & (count < k).

    cond = F.lit(False)
    for m_col in measure_cols:
        c = F.col(m_col)
        cond = cond | ((c > 0) & (c < k))

    # Apply redaction
    ret_df = df
    for dim_name, dtype in dimension_cols:
        # If unsafe, use redacted value, else original
        safe_val = F.col(dim_name)
        redacted = redact_value(F.col(dim_name), dtype)

        ret_df = ret_df.withColumn(dim_name, F.when(cond, redacted).otherwise(safe_val))

    return ret_df
