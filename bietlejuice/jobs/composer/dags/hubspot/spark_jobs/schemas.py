from pyspark.sql.types import (
    StructType,
    StructField,
    StringType,
    IntegerType,
    TimestampType,
    BooleanType,
    MapType,
    ArrayType,
)


class HubSpotSchemaEnum:
    """This class contains the Spark schemas for the tables loaded by the HubSpot Consumer."""

    PIPELINE_SCHEMA = StructType(
        [
            StructField("label", StringType(), True),
            StructField("display_order", IntegerType(), True),
            StructField("id", StringType(), True),
            StructField(
                "stages",
                ArrayType(
                    StructType(
                        [
                            StructField("label", StringType(), True),
                            StructField("display_order", IntegerType(), True),
                            StructField(
                                "metadata", MapType(StringType(), StringType()), True
                            ),
                            StructField("id", StringType(), True),
                            StructField("created_at", TimestampType(), True),
                            StructField("archived_at", TimestampType(), True),
                            StructField("updated_at", TimestampType(), True),
                            StructField("archived", BooleanType(), True),
                        ]
                    )
                ),
                True,
            ),
            StructField("created_at", TimestampType(), True),
            StructField("archived_at", TimestampType(), True),
            StructField("updated_at", TimestampType(), True),
            StructField("archived", BooleanType(), True),
        ]
    )
    TEAM_SCHEMA = StructType(
        [
            StructField("id", StringType(), True),
            StructField("name", StringType(), True),
            StructField("user_ids", ArrayType(StringType()), True),
            StructField("secondary_user_ids", ArrayType(StringType()), True),
        ]
    )
    OWNER_SCHEMA = StructType(
        [
            StructField("id", StringType(), True),
            StructField("email", StringType(), True),
            StructField("first_name", StringType(), True),
            StructField("last_name", StringType(), True),
            StructField("user_id", IntegerType(), True),
            StructField("created_at", TimestampType(), True),
            StructField("updated_at", TimestampType(), True),
            StructField("archived", BooleanType(), True),
            StructField(
                "teams",
                ArrayType(
                    StructType(
                        [
                            StructField("id", StringType(), True),
                            StructField("name", StringType(), True),
                            StructField("membership", StringType(), True),
                        ]
                    )
                ),
            ),
        ]
    )
    OBJECT_SCHEMA = StructType(
        [
            StructField("id", StringType(), True),
            StructField("properties", StringType(), True),
            StructField("properties_with_history", StringType(), True),
            StructField("created_at", TimestampType(), True),
            StructField("updated_at", TimestampType(), True),
            StructField("archived", BooleanType(), True),
            StructField("archived_at", TimestampType(), True),
            StructField("associations", StringType(), True),
        ]
    )
