# Salesforce Types to Pyspark for events and API


from pyspark.sql.types import (
    BooleanType,
    DoubleType,
    LongType,
    StringType,
    StructField,
    StructType,
)


def salesforce_type_to_pyspark_type(field, sf_type):
    if sf_type == "boolean":
        return (field, BooleanType())

    if sf_type in ("int", "integer"):
        return (field, LongType())

    if sf_type in ("double",):
        return (field, DoubleType())

    if sf_type in ("date", "datetime", "time"):
        return (field, StringType())

    # IDs, references, picklists, text, textarea, email, url, phone, etc.
    return (field, StringType())


# For API we can keep some values instead of string
def build_salesforce_type_schema(field_lst):
    """
    Build a Spark StructType from Salesforce field names and type strings.

    Maps each pair through ``salesforce_type_to_pyspark_type`` so booleans,
    integers, doubles, and timestamps use native Spark types where applicable.
    All fields are nullable.

    """
    return StructType(
        [
            StructField(*salesforce_type_to_pyspark_type(name, sf_type), True)
            for name, sf_type in field_lst
        ]
    )


# For CDC let's keep all values as String
def schema_define(cols):
    """
    Build a StructType with every column as nullable StringType.

    Used for CDC payloads where values stay as strings for downstream parsing.

    """
    return StructType([StructField(col, StringType(), True) for col in cols])
