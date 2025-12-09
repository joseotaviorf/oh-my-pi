from typing import Any, Dict

from pyspark.sql import DataFrame
from pyspark.sql.types import (
    ArrayType,
    BinaryType,
    BooleanType,
    DateType,
    DecimalType,
    DoubleType,
    FloatType,
    IntegerType,
    LongType,
    StringType,
    TimestampNTZType,
    TimestampType,
)

SIMPLE_TYPE_MAPPINGS = {
    BinaryType: {"type": "string"},
    BooleanType: {"type": "boolean"},
    DateType: {"type": "string"},
    DecimalType: {"type": "number"},
    DoubleType: {"type": "number"},
    FloatType: {"type": "number"},
    IntegerType: {"type": "integer"},
    LongType: {"type": "integer"},
    StringType: {"type": "string"},
    TimestampNTZType: {"type": "string"},
    TimestampType: {"type": "string"},
}


def _add_nullable_support(schema: Dict[str, Any]) -> Dict[str, Any]:
    """Add null type to schema for nullable fields."""
    result = schema.copy()
    if "type" in result:
        current_type = result["type"]
        if isinstance(current_type, str):
            result["type"] = [current_type, "null"]
    return result


def _convert_complex_type(spark_type) -> Dict[str, Any]:
    """Convert complex Spark types to JSON Schema recursively."""
    if isinstance(spark_type, ArrayType):
        return {
            "type": "array",
            "items": _spark_type_to_json_schema_type(spark_type.elementType),
        }

    raise ValueError("Unknown complex type: " + spark_type.__class__.__name__)


def _spark_type_to_json_schema_type(spark_type) -> Dict[str, Any]:
    """Convert Spark data type to JSON Schema type definition."""
    spark_type_class = type(spark_type)

    if spark_type_class in SIMPLE_TYPE_MAPPINGS:
        return SIMPLE_TYPE_MAPPINGS[spark_type_class].copy()

    return _convert_complex_type(spark_type)


def generate_json_schema_from_dataframe(
    df: DataFrame, schema_name: str
) -> Dict[str, Any]:
    """Generate JSON Schema from Spark DataFrame schema."""
    properties = {}
    required = []

    for field in df.schema.fields:
        field_schema = _spark_type_to_json_schema_type(field.dataType)

        if field.nullable:
            field_schema = _add_nullable_support(field_schema)
        else:
            required.append(field.name)

        properties[field.name] = field_schema

    json_schema = {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "title": schema_name,
        "description": f"JSON Schema for {schema_name}",
        "type": "object",
        "properties": properties,
    }

    if required:
        json_schema["required"] = required

    json_schema["additionalProperties"] = False

    return json_schema
