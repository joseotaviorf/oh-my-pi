import pyspark.sql.functions as F
from pyspark.sql import Column, DataFrame
from pyspark.sql.types import DataType, StringType, StructType, _parse_datatype_string


def build_change_events_fields(
    df: DataFrame,
    id_col: str,
    event_type: str,
    entity_name: str,
    date_col: str,
    source_file: str,
    layer="raw",
) -> DataFrame:
    """Shape API backfill rows so they satisfy the CDC table contract.

    Change Data Capture payloads normally ship every mandatory control field.
    Bulk or snapshot pulls from the REST API do not; this helper **adds those
    required CDC columns** (identifiers, entity metadata, synthetic commit
    sequence, lineage) using values from the API row plus caller literals, then
    keeps all remaining API columns as-is at the end of the projection.

    The synthetic ``transaction_key`` is ``sha256`` of a constant prefix
    concatenated with ``commit_ts``, so backfilled rows stay distinguishable
    from keys emitted by the live CDC stream.

    Args:
        df: Salesforce (or similar) API payload as a Spark ``DataFrame``.
        id_col: Source column mapped to ``id_record``.
        event_type: Literal written to ``event_type`` (e.g. ``RECOVERED``).
        entity_name: Literal written to ``entity_name``.
        date_col: Source column parsed as ``commit_ts`` (ISO-8601 with zone).
        source_file: Literal written to ``source_file`` for lineage.

    Returns:
        ``DataFrame`` with CDC-ordered leading columns plus remaining API fields.
    """
    parsed_commit_ts = F.to_timestamp(date_col, "yyyy-MM-dd'T'HH:mm:ss.SSSZ")

    change_event_header = (
        "change_event_header" if layer == "clean" else "ChangeEventHeader"
    )
    new_first_columns = [
        F.col(id_col).alias("id_record"),
        F.lit(entity_name).alias("entity_name"),
        F.lit(event_type).alias("event_type"),
        F.lit(None).alias(change_event_header),
        F.sha2(
            F.concat_ws(
                "||",
                F.lit(event_type),
                parsed_commit_ts,
            ),
            256,
        ).alias("transaction_key"),
        F.lit(1).cast("bigint").alias("sequence_number"),
        F.lit(1).cast("bigint").alias("commit_number"),
        parsed_commit_ts.alias("commit_ts"),
        F.col("CreatedById").alias("commit_user"),
        F.array().alias("changed_field"),
        F.lit(source_file).alias("source_file"),
    ]

    new_col_names = {
        "id_record",
        "entity_name",
        "event_type",
        "change_event_header",
        "transaction_key",
        "sequence_number",
        "commit_number",
        "commit_ts",
        "commit_user",
        "changed_field",
        "source_file",
    }

    original_columns = [
        F.col(col_name) for col_name in df.columns if col_name not in new_col_names
    ]
    return df.select(*new_first_columns, *original_columns)


def first_letter_lower(value: str) -> str:
    # First Letter to Lower, to convert to API version
    return value[:1].lower() + value[1:]


def first_letter_upper(value: str) -> str:
    # First Letter to Upper, to restore to CDC pattern
    return value[:1].upper() + value[1:]


def parse_struct_fields_to_api_format(struct_type: str) -> list[tuple[str, str]]:
    """
    Parse the CDC type of struct from our target_table and convert the first letter to lowercase
    So columns like this in CDC CountryCode will be converted to countryCode (API version)
    """
    inner = struct_type.removeprefix("struct<").removesuffix(">")
    return [
        (first_letter_lower(column_name), column_type)
        for column_name, column_type in (
            field.split(":", 1) for field in inner.split(",")
        )
    ]


def cast_string_to_boolean(col_name: str):
    normalized = F.lower(F.trim(F.col(col_name)))

    return (
        F.when(normalized == "true", F.lit(True))
        .when(normalized == "false", F.lit(False))
        .otherwise(F.lit(None).cast("boolean"))
    )


def parse_struct_column(dtype: str, col_name: str, target_schema: StructType):
    """
    Parse a struct column from a string to a struct type
    If the column is a string, it will be parsed to a struct type
    If the column is already a struct type, it will be cast to the target schema
    If the column is not a string or a struct type, it will be returned as is
    """
    if isinstance(dtype, StringType):
        return F.from_json(F.col(col_name), target_schema)

    if isinstance(dtype, StructType):
        return F.col(col_name).cast(target_schema)

    return F.lit(None).cast(target_schema)


def parse_ddl(ddl: str) -> DataType:
    if hasattr(DataType, "fromDDL"):
        return DataType.fromDDL(ddl)

    return _parse_datatype_string(ddl)


def remap_struct_expr(col_name: str, target_col: str) -> Column:
    """
    Returns a Column expression that:
      1. parses API JSON string using lowerCamelCase fields
      2. rebuilds the struct using prod UpperCamelCase fields
    """
    original_struct_type = parse_ddl(target_col)

    if not isinstance(original_struct_type, StructType):
        raise ValueError(
            f"target_col must be a struct type. Got: {original_struct_type}"
        )

    api_fields = parse_struct_fields_to_api_format(target_col)

    api_struct_string = (
        "struct<"
        + ",".join(
            f"{field_name}:{field_type}" for field_name, field_type in api_fields
        )
        + ">"
    )

    api_struct_type = parse_ddl(api_struct_string)

    parsed_col = F.from_json(F.col(col_name), api_struct_type)

    remapped_fields = [
        parsed_col.getField(first_letter_lower(field.name))
        .cast(field.dataType)
        .alias(field.name)
        for field in original_struct_type.fields
    ]

    return F.struct(*remapped_fields)
