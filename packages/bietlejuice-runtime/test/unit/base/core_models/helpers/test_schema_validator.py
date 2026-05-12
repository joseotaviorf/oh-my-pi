from datetime import date, datetime
from decimal import Decimal
from unittest.mock import Mock

import pytest
from pyspark.sql.types import (
    BinaryType,
    BooleanType,
    DateType,
    DecimalType,
    DoubleType,
    FloatType,
    IntegerType,
    LongType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)

from bietlejuice.base.core_models.helpers.schema_validator import (
    SchemaValidationError,
    SchemaValidator,
)


class TestSchemaValidator:
    """Test cases for SchemaValidator class."""

    def test_init(self):
        """Test SchemaValidator initialization."""
        validator = SchemaValidator()
        assert validator is not None
        assert hasattr(validator, "_type_mapping")
        assert "string" in validator._type_mapping
        assert "int" in validator._type_mapping

    def test_validate_schema_success_basic(self, spark_session):
        """Test successful basic schema validation."""
        # Arrange
        validator = SchemaValidator()

        schema = StructType(
            [
                StructField("id", StringType(), True),
                StructField("name", StringType(), True),
                StructField("age", IntegerType(), True),
            ]
        )
        data = [("1", "John", 30), ("2", "Jane", 25)]
        df = spark_session.createDataFrame(data, schema)

        expected_schema = {
            "columns": {
                "id": {"type": "string", "nullable": True},
                "name": {"type": "string", "nullable": True},
                "age": {"type": "int", "nullable": True},
            }
        }

        # Act & Assert
        result = validator.validate_schema(df, expected_schema)
        assert result is True

    def test_validate_schema_success_strict_mode(self, spark_session):
        """Test successful schema validation in strict mode."""
        # Arrange
        validator = SchemaValidator()

        schema = StructType(
            [
                StructField("id", StringType(), True),
                StructField("name", StringType(), True),
            ]
        )
        data = [("1", "John"), ("2", "Jane")]
        df = spark_session.createDataFrame(data, schema)

        expected_schema = {
            "columns": {
                "id": {"type": "string", "nullable": True},
                "name": {"type": "string", "nullable": True},
            },
            "strict": True,
        }

        # Act & Assert
        result = validator.validate_schema(df, expected_schema)
        assert result is True

    def test_validate_schema_missing_required_column(self, spark_session):
        """Test validation failure for missing required column."""
        # Arrange
        validator = SchemaValidator()

        schema = StructType([StructField("id", StringType(), True)])
        data = [("1",), ("2",)]
        df = spark_session.createDataFrame(data, schema)

        expected_schema = {
            "columns": {
                "id": {"type": "string", "nullable": True, "required": True},
                "name": {"type": "string", "nullable": True, "required": True},
            }
        }

        # Act & Assert
        with pytest.raises(SchemaValidationError) as exc_info:
            validator.validate_schema(df, expected_schema)

        assert "Required column 'name' is missing" in str(exc_info.value)

    def test_validate_schema_type_mismatch(self, spark_session):
        """Test validation failure for type mismatch."""
        # Arrange
        validator = SchemaValidator()

        schema = StructType(
            [
                StructField("id", StringType(), True),
                StructField("age", StringType(), True),  # Should be int
            ]
        )
        data = [("1", "30"), ("2", "25")]
        df = spark_session.createDataFrame(data, schema)

        expected_schema = {
            "columns": {
                "id": {"type": "string", "nullable": True},
                "age": {"type": "int", "nullable": True},
            }
        }

        # Act & Assert
        with pytest.raises(SchemaValidationError) as exc_info:
            validator.validate_schema(df, expected_schema)

        assert "Column 'age' type mismatch" in str(exc_info.value)
        assert "expected int" in str(exc_info.value)

    def test_validate_schema_nullable_mismatch(self, spark_session):
        """Test validation failure for nullable mismatch."""
        # Arrange
        validator = SchemaValidator()

        schema = StructType(
            [
                StructField("id", StringType(), True),  # nullable=True
                StructField("name", StringType(), False),  # nullable=False
            ]
        )
        data = [("1", "John"), ("2", "Jane")]
        df = spark_session.createDataFrame(data, schema)

        expected_schema = {
            "columns": {
                "id": {"type": "string", "nullable": False},  # Expect non-nullable
                "name": {"type": "string", "nullable": True},  # Expect nullable
            }
        }

        # Act & Assert
        with pytest.raises(SchemaValidationError) as exc_info:
            validator.validate_schema(df, expected_schema)

        error_message = str(exc_info.value)
        assert "nullable mismatch" in error_message

    def test_validate_schema_strict_mode_extra_columns(self, spark_session):
        """Test validation failure in strict mode with extra columns."""
        # Arrange
        validator = SchemaValidator()

        schema = StructType(
            [
                StructField("id", StringType(), True),
                StructField("name", StringType(), True),
                StructField("extra", StringType(), True),  # Extra column
            ]
        )
        data = [("1", "John", "extra_data")]
        df = spark_session.createDataFrame(data, schema)

        expected_schema = {
            "columns": {
                "id": {"type": "string", "nullable": True},
                "name": {"type": "string", "nullable": True},
            },
            "strict": True,
        }

        # Act & Assert
        with pytest.raises(SchemaValidationError) as exc_info:
            validator.validate_schema(df, expected_schema)

        assert "Unexpected columns in strict mode" in str(exc_info.value)
        assert "extra" in str(exc_info.value)

    def test_validate_schema_column_count_constraints(self, spark_session):
        """Test column count validation constraints."""
        # Arrange
        validator = SchemaValidator()

        schema = StructType(
            [
                StructField("id", StringType(), True),
                StructField("name", StringType(), True),
            ]
        )
        data = [("1", "John")]
        df = spark_session.createDataFrame(data, schema)

        # Test min_columns constraint
        expected_schema_min = {"min_columns": 3}

        with pytest.raises(SchemaValidationError) as exc_info:
            validator.validate_schema(df, expected_schema_min)

        assert "Too few columns" in str(exc_info.value)
        assert "expected at least 3, got 2" in str(exc_info.value)

        # Test max_columns constraint
        expected_schema_max = {"max_columns": 1}

        with pytest.raises(SchemaValidationError) as exc_info:
            validator.validate_schema(df, expected_schema_max)

        assert "Too many columns" in str(exc_info.value)
        assert "expected at most 1, got 2" in str(exc_info.value)

    def test_validate_schema_none_dataframe(self):
        """Test validation with None DataFrame."""
        # Arrange
        validator = SchemaValidator()
        expected_schema = {"columns": {}}

        # Act & Assert
        with pytest.raises(SchemaValidationError) as exc_info:
            validator.validate_schema(None, expected_schema)

        assert "DataFrame is None" in str(exc_info.value)

    def test_validate_schema_optional_columns(self, spark_session):
        """Test validation with optional columns."""
        # Arrange
        validator = SchemaValidator()

        schema = StructType([StructField("id", StringType(), True)])
        data = [("1",), ("2",)]
        df = spark_session.createDataFrame(data, schema)

        expected_schema = {
            "columns": {
                "id": {"type": "string", "nullable": True, "required": True},
                "optional_field": {
                    "type": "string",
                    "nullable": True,
                    "required": False,
                },
            }
        }

        # Act & Assert - Should pass since optional_field is not required
        result = validator.validate_schema(df, expected_schema)
        assert result is True

    def test_validate_schema_multiple_errors(self, spark_session):
        """Test validation collects multiple errors."""
        # Arrange
        validator = SchemaValidator()

        schema = StructType(
            [
                StructField("id", StringType(), True),
                StructField("age", StringType(), True),  # Wrong type
            ]
        )
        data = [("1", "30")]
        df = spark_session.createDataFrame(data, schema)

        expected_schema = {
            "columns": {
                "id": {"type": "string", "nullable": True},
                "age": {"type": "int", "nullable": True},
                "missing_field": {"type": "string", "required": True},
            },
            "min_columns": 5,  # Too many required
        }

        # Act & Assert
        with pytest.raises(SchemaValidationError) as exc_info:
            validator.validate_schema(df, expected_schema)

        error_message = str(exc_info.value)
        assert "Required column 'missing_field' is missing" in error_message
        assert "Column 'age' type mismatch" in error_message
        assert "Too few columns" in error_message

    def test_type_compatibility_numeric_types(self, spark_session):
        """Test numeric type compatibility."""
        # Arrange
        validator = SchemaValidator()

        # Test int/long compatibility
        schema_long = StructType([StructField("value", LongType(), True)])
        data = [(100,)]
        df_long = spark_session.createDataFrame(data, schema_long)

        expected_schema_int = {"columns": {"value": {"type": "int", "nullable": True}}}

        # Should pass due to numeric compatibility
        result = validator.validate_schema(df_long, expected_schema_int)
        assert result is True

        # Test float/double compatibility
        schema_double = StructType([StructField("value", DoubleType(), True)])
        data = [(100.5,)]
        df_double = spark_session.createDataFrame(data, schema_double)

        expected_schema_float = {
            "columns": {"value": {"type": "float", "nullable": True}}
        }

        # Should pass due to numeric compatibility
        result = validator.validate_schema(df_double, expected_schema_float)
        assert result is True


class TestSchemaValidatorUtilityMethods:
    """Test cases for SchemaValidator utility methods."""

    def test_get_schema_summary_success(self, spark_session):
        """Test successful schema summary generation."""
        # Arrange
        validator = SchemaValidator()

        schema = StructType(
            [
                StructField("id", StringType(), False),
                StructField("name", StringType(), True),
                StructField("age", IntegerType(), True),
            ]
        )
        data = [("1", "John", 30)]
        df = spark_session.createDataFrame(data, schema)

        # Act
        summary = validator.get_schema_summary(df)

        # Assert
        assert "column_count" in summary
        assert summary["column_count"] == 3
        assert "columns" in summary
        assert "id" in summary["columns"]
        assert "name" in summary["columns"]
        assert "age" in summary["columns"]

        # Check column details
        assert summary["columns"]["id"]["type"] == "string"
        assert summary["columns"]["id"]["nullable"] is False
        assert summary["columns"]["name"]["nullable"] is True
        assert "int" in summary["columns"]["age"]["type"].lower()

    def test_get_schema_summary_none_dataframe(self):
        """Test schema summary with None DataFrame."""
        # Arrange
        validator = SchemaValidator()

        # Act
        summary = validator.get_schema_summary(None)

        # Assert
        assert "error" in summary
        assert "DataFrame is None" in summary["error"]

    def test_get_schema_summary_with_exception(self):
        """Test schema summary handles exceptions."""
        # Arrange
        validator = SchemaValidator()
        mock_df = Mock()
        mock_df.columns = Mock(side_effect=Exception("Test error"))

        # Act
        summary = validator.get_schema_summary(mock_df)

        # Assert
        assert "error" in summary
        assert "Failed to get schema summary" in summary["error"]

    def test_create_schema_from_dataframe_success(self, spark_session):
        """Test successful schema creation from DataFrame."""
        # Arrange
        validator = SchemaValidator()

        schema = StructType(
            [
                StructField("id", StringType(), False),
                StructField("name", StringType(), True),
                StructField("age", IntegerType(), True),
                StructField("is_active", BooleanType(), False),
                StructField("created_at", TimestampType(), True),
                StructField("birth_date", DateType(), True),
            ]
        )
        data = [("1", "John", 30, True, datetime.now(), date.today())]
        df = spark_session.createDataFrame(data, schema)

        # Act
        created_schema = validator.create_schema_from_dataframe(df, strict=True)

        # Assert
        assert "columns" in created_schema
        assert "strict" in created_schema
        assert created_schema["strict"] is True

        columns = created_schema["columns"]
        assert len(columns) == 6

        # Check each column
        assert columns["id"]["type"] == "string"
        assert columns["id"]["nullable"] is False
        assert columns["id"]["required"] is True

        assert columns["name"]["type"] == "string"
        assert columns["name"]["nullable"] is True

        assert columns["age"]["type"] == "int"
        assert columns["is_active"]["type"] == "boolean"
        assert columns["created_at"]["type"] == "timestamp"
        assert columns["birth_date"]["type"] == "date"

    def test_create_schema_from_dataframe_none(self):
        """Test schema creation with None DataFrame."""
        # Arrange
        validator = SchemaValidator()

        # Act & Assert
        with pytest.raises(ValueError) as exc_info:
            validator.create_schema_from_dataframe(None)

        assert "DataFrame is None" in str(exc_info.value)

    def test_create_schema_from_dataframe_not_strict(self, spark_session):
        """Test schema creation with strict=False."""
        # Arrange
        validator = SchemaValidator()

        schema = StructType([StructField("id", StringType(), True)])
        data = [("1",)]
        df = spark_session.createDataFrame(data, schema)

        # Act
        created_schema = validator.create_schema_from_dataframe(df, strict=False)

        # Assert
        assert created_schema["strict"] is False


class TestSchemaValidatorTypeMappings:
    """Test cases for type mappings and conversions."""

    def test_type_mapping_initialization(self):
        """Test that type mappings are properly initialized."""
        # Arrange & Act
        validator = SchemaValidator()

        # Assert
        expected_mappings = {
            "string": "StringType",
            "int": "IntegerType",
            "integer": "IntegerType",
            "long": "LongType",
            "bigint": "LongType",
            "double": "DoubleType",
            "float": "FloatType",
            "boolean": "BooleanType",
            "timestamp": "TimestampType",
            "date": "DateType",
            "binary": "BinaryType",
            "decimal": "DecimalType",
        }

        for key, expected_value in expected_mappings.items():
            assert key in validator._type_mapping
            assert validator._type_mapping[key] == expected_value

    def test_spark_type_to_simple_conversion(self):
        """Test conversion from Spark types to simple type names."""
        # Arrange
        validator = SchemaValidator()

        # Test cases: (spark_type, expected_simple_type)
        test_cases = [
            ("StringType", "string"),
            ("stringtype", "string"),
            ("IntegerType", "int"),
            ("integertype", "int"),
            ("LongType", "long"),
            ("longtype", "long"),
            ("DoubleType", "double"),
            ("doubletype", "double"),
            ("FloatType", "float"),
            ("floattype", "float"),
            ("BooleanType", "boolean"),
            ("booleantype", "boolean"),
            ("TimestampType", "timestamp"),
            ("timestamptype", "timestamp"),
            ("DateType", "date"),
            ("datetype", "date"),
            ("BinaryType", "binary"),
            ("binarytype", "binary"),
            ("UnknownType", "UnknownType"),  # Should return original if no mapping
        ]

        # Act & Assert
        for spark_type, expected in test_cases:
            result = validator._spark_type_to_simple(spark_type)
            assert (
                result == expected
            ), f"Failed for {spark_type}: expected {expected}, got {result}"

    def test_is_compatible_numeric_type(self):
        """Test numeric type compatibility checking."""
        # Arrange
        validator = SchemaValidator()

        # Test integer compatibility
        assert validator._is_compatible_numeric_type("int", "integertype") is True
        assert validator._is_compatible_numeric_type("integer", "longtype") is True
        assert validator._is_compatible_numeric_type("long", "bigint") is True
        assert validator._is_compatible_numeric_type("bigint", "int") is True

        # Test float compatibility
        assert validator._is_compatible_numeric_type("float", "doubletype") is True
        assert validator._is_compatible_numeric_type("double", "floattype") is True

        # Test non-compatible types
        assert validator._is_compatible_numeric_type("string", "integertype") is False
        assert validator._is_compatible_numeric_type("int", "stringtype") is False
        assert validator._is_compatible_numeric_type("boolean", "doubletype") is False


class TestSchemaValidatorComplexTypes:
    """Test cases for complex data types and edge cases."""

    def test_validate_schema_with_all_spark_types(self, spark_session):
        """Test validation with all supported Spark data types."""
        # Arrange
        validator = SchemaValidator()

        schema = StructType(
            [
                StructField("str_col", StringType(), True),
                StructField("int_col", IntegerType(), True),
                StructField("long_col", LongType(), True),
                StructField("double_col", DoubleType(), True),
                StructField("float_col", FloatType(), True),
                StructField("bool_col", BooleanType(), True),
                StructField("timestamp_col", TimestampType(), True),
                StructField("date_col", DateType(), True),
                StructField("binary_col", BinaryType(), True),
                StructField("decimal_col", DecimalType(10, 2), True),
            ]
        )

        data = [
            (
                "test",
                123,
                123456789,
                123.45,
                123.45,
                True,
                datetime.now(),
                date.today(),
                b"binary_data",
                Decimal("123.45"),
            )
        ]
        df = spark_session.createDataFrame(data, schema)

        expected_schema = {
            "columns": {
                "str_col": {"type": "string", "nullable": True},
                "int_col": {"type": "int", "nullable": True},
                "long_col": {"type": "long", "nullable": True},
                "double_col": {"type": "double", "nullable": True},
                "float_col": {"type": "float", "nullable": True},
                "bool_col": {"type": "boolean", "nullable": True},
                "timestamp_col": {"type": "timestamp", "nullable": True},
                "date_col": {"type": "date", "nullable": True},
                "binary_col": {"type": "binary", "nullable": True},
                "decimal_col": {"type": "decimal", "nullable": True},
            }
        }

        # Act & Assert
        result = validator.validate_schema(df, expected_schema)
        assert result is True

    def test_validate_schema_with_case_insensitive_types(self, spark_session):
        """Test type validation is case insensitive."""
        # Arrange
        validator = SchemaValidator()

        schema = StructType([StructField("test_col", StringType(), True)])
        data = [("test",)]
        df = spark_session.createDataFrame(data, schema)

        expected_schema = {
            "columns": {"test_col": {"type": "STRING", "nullable": True}}  # Uppercase
        }

        # Act & Assert
        result = validator.validate_schema(df, expected_schema)
        assert result is True

    def test_validate_schema_empty_dataframe(self, spark_session):
        """Test validation with empty DataFrame."""
        # Arrange
        validator = SchemaValidator()

        schema = StructType(
            [
                StructField("id", StringType(), True),
                StructField("name", StringType(), True),
            ]
        )
        df = spark_session.createDataFrame([], schema)

        expected_schema = {
            "columns": {
                "id": {"type": "string", "nullable": True},
                "name": {"type": "string", "nullable": True},
            }
        }

        # Act & Assert
        result = validator.validate_schema(df, expected_schema)
        assert result is True

    def test_validate_schema_empty_schema_definition(self, spark_session):
        """Test validation with empty schema definition."""
        # Arrange
        validator = SchemaValidator()

        schema = StructType([StructField("id", StringType(), True)])
        data = [("1",)]
        df = spark_session.createDataFrame(data, schema)

        empty_schema = {}

        # Act & Assert - Should pass since no constraints are specified
        result = validator.validate_schema(df, empty_schema)
        assert result is True


class TestSchemaValidationError:
    """Test cases for SchemaValidationError exception."""

    def test_schema_validation_error_inheritance(self):
        """Test that SchemaValidationError is properly inherited."""
        # Arrange & Act
        error = SchemaValidationError("Test message")

        # Assert
        assert isinstance(error, Exception)
        assert str(error) == "Test message"

    def test_schema_validation_error_with_multiple_errors(self):
        """Test SchemaValidationError with multiple error messages."""
        # Arrange
        error_message = (
            "Schema validation failed with the following errors:\nError 1\nError 2"
        )

        # Act
        error = SchemaValidationError(error_message)

        # Assert
        assert "Error 1" in str(error)
        assert "Error 2" in str(error)
        assert "Schema validation failed" in str(error)


class TestSchemaValidatorEdgeCases:
    """Test cases for edge cases and error conditions."""

    def test_validate_basic_structure_with_exception(self):
        """Test _validate_basic_structure handles DataFrame access exceptions."""
        # Arrange
        validator = SchemaValidator()
        mock_df = Mock()
        # Make accessing columns or schema raise an exception
        type(mock_df).columns = property(Mock(side_effect=Exception("Access error")))
        type(mock_df).schema = property(
            Mock(side_effect=Exception("Schema access error"))
        )

        # Act
        errors = validator._validate_basic_structure(mock_df, {})

        # Assert
        assert len(errors) > 0
        assert "Failed to access DataFrame schema" in errors[0]

    def test_validate_columns_with_none_dataframe(self):
        """Test _validate_columns handles None DataFrame."""
        # Arrange
        validator = SchemaValidator()
        column_schema = {"id": {"type": "string"}}

        # Act
        errors = validator._validate_columns(None, column_schema)

        # Assert
        assert errors == []

    def test_validate_columns_optional_column_not_required(self, spark_session):
        """Test _validate_columns skips validation for optional columns that don't exist."""
        # Arrange
        validator = SchemaValidator()
        schema = StructType([StructField("id", StringType(), True)])
        df = spark_session.createDataFrame([("1",)], schema)
        column_schema = {
            "id": {"type": "string", "required": True},
            "optional": {"type": "string", "required": False},
        }

        # Act
        errors = validator._validate_columns(df, column_schema)

        # Assert
        assert errors == []

    def test_validate_column_type_with_datatype_object(self, spark_session):
        """Test _validate_column_type with DataType object."""
        # Arrange
        validator = SchemaValidator()
        schema = StructType([StructField("id", StringType(), True)])
        df = spark_session.createDataFrame([("1",)], schema)
        field = df.schema.fields[0]

        # Act - Pass DataType object instead of string
        errors = validator._validate_column_type("id", field, StringType())

        # Assert
        assert errors == []

    def test_validate_column_type_with_datatype_mismatch(self, spark_session):
        """Test _validate_column_type with DataType object mismatch."""
        # Arrange
        validator = SchemaValidator()
        schema = StructType([StructField("id", StringType(), True)])
        df = spark_session.createDataFrame([("1",)], schema)
        field = df.schema.fields[0]

        # Act - Pass different DataType object
        errors = validator._validate_column_type("id", field, IntegerType())

        # Assert
        assert len(errors) > 0
        assert "type mismatch" in errors[0].lower()

    def test_validate_column_type_custom_type_not_in_mapping(self, spark_session):
        """Test _validate_column_type with custom type not in mapping."""
        # Arrange
        validator = SchemaValidator()
        schema = StructType([StructField("id", StringType(), True)])
        df = spark_session.createDataFrame([("1",)], schema)
        field = df.schema.fields[0]

        # Act - Use custom type not in mapping
        errors = validator._validate_column_type("id", field, "customtype")

        # Assert
        assert len(errors) > 0
        assert "type mismatch" in errors[0].lower()

    def test_is_compatible_numeric_type_integer_compatibility(self):
        """Test _is_compatible_numeric_type for integer types."""
        # Arrange
        validator = SchemaValidator()

        # Act & Assert
        assert validator._is_compatible_numeric_type("int", "integertype") is True
        assert validator._is_compatible_numeric_type("integer", "longtype") is True
        assert validator._is_compatible_numeric_type("long", "bigint") is True
        assert validator._is_compatible_numeric_type("bigint", "int") is True
        assert validator._is_compatible_numeric_type("int", "stringtype") is False

    def test_is_compatible_numeric_type_float_compatibility(self):
        """Test _is_compatible_numeric_type for float types."""
        # Arrange
        validator = SchemaValidator()

        # Act & Assert
        assert validator._is_compatible_numeric_type("float", "doubletype") is True
        assert validator._is_compatible_numeric_type("double", "floattype") is True
        assert validator._is_compatible_numeric_type("float", "integertype") is False

    def test_validate_column_count_with_none_dataframe(self):
        """Test _validate_column_count handles None DataFrame."""
        # Arrange
        validator = SchemaValidator()
        schema = {"min_columns": 5}

        # Act
        errors = validator._validate_column_count(None, schema)

        # Assert
        assert errors == []

    def test_validate_strict_mode_with_none_dataframe(self):
        """Test _validate_strict_mode handles None DataFrame."""
        # Arrange
        validator = SchemaValidator()
        schema = {"columns": {"id": {"type": "string"}}, "strict": True}

        # Act
        errors = validator._validate_strict_mode(None, schema)

        # Assert
        assert errors == []

    def test_validate_strict_mode_without_columns_in_schema(self, spark_session):
        """Test _validate_strict_mode when columns not in schema."""
        # Arrange
        validator = SchemaValidator()
        schema = StructType([StructField("id", StringType(), True)])
        df = spark_session.createDataFrame([("1",)], schema)
        schema_def = {"strict": True}  # No columns key

        # Act
        errors = validator._validate_strict_mode(df, schema_def)

        # Assert
        assert errors == []

    def test_spark_type_to_simple_unmapped_type(self):
        """Test _spark_type_to_simple with unmapped type."""
        # Arrange
        validator = SchemaValidator()

        # Act
        result = validator._spark_type_to_simple("UnknownComplexType")

        # Assert
        assert result == "UnknownComplexType"

    def test_spark_type_to_simple_with_complex_type_name(self):
        """Test _spark_type_to_simple with complex type name."""
        # Arrange
        validator = SchemaValidator()

        # Act - Use a type that doesn't match any mapping
        result = validator._spark_type_to_simple("MapType")

        # Assert
        # Should return original if no mapping found
        assert result == "MapType"


# Pytest markers for conditional test execution
pytestmark = [pytest.mark.unit, pytest.mark.core_models, pytest.mark.schema_validation]
