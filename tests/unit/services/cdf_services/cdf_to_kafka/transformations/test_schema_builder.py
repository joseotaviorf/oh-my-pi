"""Unit tests for schema_builder module."""

import pytest
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
    MapType,
    StringType,
    StructField,
    StructType,
    TimestampNTZType,
    TimestampType,
)

from bietlejuice.services.cdf_services.cdf_to_kafka.transformations.schema_builder import (
    _add_nullable_support,
    _convert_complex_type,
    _spark_type_to_json_schema_type,
    generate_json_schema_from_dataframe,
)


class TestAddNullableSupport:
    """Tests for _add_nullable_support function."""

    @pytest.mark.parametrize(
        "input_type,expected_type",
        [
            ("string", ["string", "null"]),
            ("integer", ["integer", "null"]),
            ("boolean", ["boolean", "null"]),
            ("number", ["number", "null"]),
        ],
    )
    def test_adds_null_to_type(self, input_type, expected_type):
        """Test adding null support to various types."""
        schema = {"type": input_type, "description": "A test field"}

        result = _add_nullable_support(schema)

        assert result["type"] == expected_type
        assert result["description"] == "A test field"
        assert schema["type"] == input_type


class TestConvertComplexType:
    """Tests for _convert_complex_type function."""

    def test_converts_array_type(self):
        """Test conversion of ArrayType."""
        spark_type = ArrayType(StringType())

        result = _convert_complex_type(spark_type)

        assert result["type"] == "array"
        assert result["items"]["type"] == "string"

    def test_converts_nested_array_type(self):
        """Test conversion of nested ArrayType."""
        spark_type = ArrayType(ArrayType(IntegerType()))

        result = _convert_complex_type(spark_type)

        assert result["type"] == "array"
        assert result["items"]["type"] == "array"
        assert result["items"]["items"]["type"] == "integer"

    def test_raises_error_for_unknown_complex_type(self):
        """Test that ValueError is raised for unknown complex types."""
        spark_type = MapType(StringType(), IntegerType())

        with pytest.raises(ValueError, match="Unknown complex type"):
            _convert_complex_type(spark_type)


class TestSparkTypeToJsonSchemaType:
    """Tests for _spark_type_to_json_schema_type function."""

    @pytest.mark.parametrize(
        "spark_type,expected_json_type",
        [
            (BinaryType(), {"type": "string"}),
            (BooleanType(), {"type": "boolean"}),
            (DateType(), {"type": "string"}),
            (DecimalType(), {"type": "number"}),
            (DoubleType(), {"type": "number"}),
            (FloatType(), {"type": "number"}),
            (IntegerType(), {"type": "integer"}),
            (LongType(), {"type": "integer"}),
            (StringType(), {"type": "string"}),
            (TimestampNTZType(), {"type": "string"}),
            (TimestampType(), {"type": "string"}),
            (ArrayType(StringType()), {"type": "array", "items": {"type": "string"}}),
        ],
    )
    def test_type_mappings(self, spark_type, expected_json_type):
        """Test mapping of Spark types to JSON Schema types."""
        result = _spark_type_to_json_schema_type(spark_type)

        assert result == expected_json_type


class TestGenerateJsonSchemaFromDataframe:
    """Tests for generate_json_schema_from_dataframe function."""

    def test_generates_schema_with_nullable_and_required_fields(self, spark_session):
        """Test generating schema with proper nullable and required handling."""
        schema = StructType(
            [
                StructField("id", IntegerType(), nullable=False),
                StructField("tenant_id", StringType(), nullable=False),
                StructField("name", StringType(), nullable=True),
                StructField("tags", ArrayType(StringType()), nullable=True),
            ]
        )
        df = spark_session.createDataFrame([], schema)

        result = generate_json_schema_from_dataframe(df, "TestSchema")

        assert result["$schema"] == "http://json-schema.org/draft-07/schema#"
        assert result["title"] == "TestSchema"
        assert result["type"] == "object"
        assert result["additionalProperties"] is False
        assert set(result["required"]) == {"id", "tenant_id"}
        assert result["properties"]["id"]["type"] == "integer"
        assert result["properties"]["name"]["type"] == ["string", "null"]
        assert "array" in result["properties"]["tags"]["type"]

    def test_empty_required_list_not_included(self, spark_session):
        """Test that empty required list is not included."""
        schema = StructType(
            [
                StructField("name", StringType(), nullable=True),
            ]
        )
        df = spark_session.createDataFrame([], schema)

        result = generate_json_schema_from_dataframe(df, "TestSchema")

        assert "required" not in result or result.get("required") == []
