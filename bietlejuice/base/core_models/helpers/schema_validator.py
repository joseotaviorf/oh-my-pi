from typing import Dict, List, Union

# Conditional PySpark imports - only import when needed to avoid CI/CD issues
try:
    from pyspark.sql import DataFrame
    from pyspark.sql.types import DataType

    PYSPARK_AVAILABLE = True
except ImportError:
    # Define dummy types for when PySpark is not available
    DataFrame = None
    DataType = None
    PYSPARK_AVAILABLE = False


class SchemaValidationError(Exception):
    """Custom exception for schema validation errors."""

    pass


class SchemaValidator:
    """
    Validates DataFrame schemas against expected schema definitions.

    Expected schema format:
    {
        "columns": {
            "column_name": {
                "type": "string|int|double|boolean|timestamp|date|...",
                "nullable": True/False,
                "required": True/False  # Column must exist
            },
            ...
        },
        "strict": True/False,  # If True, no extra columns allowed
        "min_columns": int,    # Minimum number of columns required
        "max_columns": int     # Maximum number of columns allowed
    }
    """

    # PySpark availability flag
    PYSPARK_AVAILABLE = PYSPARK_AVAILABLE

    # Centralized type mappings - can be used by other validation scripts
    VALID_SCHEMA_TYPES = [
        "string",
        "bigint",
        "int",
        "double",
        "boolean",
        "date",
        "timestamp",
        "decimal",
    ]

    TYPE_TO_SPARK_MAPPING = {
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

    SPARK_TO_TYPE_MAPPING = {
        "stringtype": "string",
        "integertype": "int",
        "longtype": "long",
        "doubletype": "double",
        "floattype": "float",
        "booleantype": "boolean",
        "timestamptype": "timestamp",
        "datetype": "date",
        "binarytype": "binary",
        "decimaltype": "decimal",
    }

    def __init__(self):
        self._type_mapping = self.TYPE_TO_SPARK_MAPPING

    def validate_schema(self, df: DataFrame, schema: dict) -> bool:
        """
        Validates a DataFrame against the expected schema.

        Args:
            df: PySpark DataFrame to validate
            schema: Schema definition dictionary

        Returns:
            bool: True if validation passes

        Raises:
            SchemaValidationError: If validation fails
            ImportError: If PySpark is not available
        """
        if not PYSPARK_AVAILABLE:
            raise ImportError(
                "PySpark is required for DataFrame validation but is not installed"
            )

        errors = []

        # Validate basic structure
        errors.extend(self._validate_basic_structure(df, schema))

        # Validate columns if specified
        if "columns" in schema:
            errors.extend(self._validate_columns(df, schema["columns"]))

        # Validate column count constraints
        errors.extend(self._validate_column_count(df, schema))

        # Check strict mode for extra columns
        if schema.get("strict", False):
            errors.extend(self._validate_strict_mode(df, schema))

        if errors:
            error_msg = (
                "Schema validation failed with the following errors:\n"
                + "\n".join(errors)
            )
            raise SchemaValidationError(error_msg)

        return True

    def _validate_basic_structure(self, df: DataFrame, schema: dict) -> List[str]:
        """Validate basic DataFrame structure."""
        errors = []

        if df is None:
            errors.append("DataFrame is None")
            return errors

        try:
            # Check if DataFrame is accessible
            df.columns  # Test accessibility
            df.schema  # Test accessibility
        except Exception as e:
            errors.append(f"Failed to access DataFrame schema: {str(e)}")
            return errors

        return errors

    def _validate_columns(self, df: DataFrame, column_schema: Dict) -> List[str]:
        """Validate individual columns against schema."""
        errors = []

        # Handle None DataFrame
        if df is None:
            return errors

        df_columns = df.columns
        df_schema_dict = {field.name: field for field in df.schema.fields}

        for column_name, column_def in column_schema.items():
            # Check if required column exists
            if column_def.get("required", True) and column_name not in df_columns:
                errors.append(f"Required column '{column_name}' is missing")
                continue

            # Skip validation if column doesn't exist and is not required
            if column_name not in df_columns:
                continue

            field = df_schema_dict[column_name]

            # Validate column type
            if "type" in column_def:
                expected_type = column_def["type"]
                errors.extend(
                    self._validate_column_type(column_name, field, expected_type)
                )

            # Validate nullable constraint
            if "nullable" in column_def:
                expected_nullable = column_def["nullable"]
                if field.nullable != expected_nullable:
                    errors.append(
                        f"Column '{column_name}' nullable mismatch: "
                        f"expected {expected_nullable}, got {field.nullable}"
                    )

        return errors

    def _validate_column_type(
        self, column_name: str, field, expected_type: Union[str, DataType]
    ) -> List[str]:
        """Validate column data type."""
        errors = []

        actual_type_name = field.dataType.simpleString().lower()

        if isinstance(expected_type, str):
            expected_type_lower = expected_type.lower()

            # Handle common type aliases and variations
            if expected_type_lower in self._type_mapping:
                expected_spark_type = self._type_mapping[expected_type_lower].lower()

                # Check for type match (remove 'type' suffix for comparison)
                expected_base = (
                    expected_spark_type.replace("type", "")
                    if expected_spark_type.endswith("type")
                    else expected_spark_type
                )

                # Check if the expected base type is in the actual type name
                if (
                    expected_base not in actual_type_name
                    and expected_spark_type not in actual_type_name
                ):
                    # Handle special cases for numeric types
                    if self._is_compatible_numeric_type(
                        expected_type_lower, actual_type_name
                    ):
                        return errors

                    errors.append(
                        f"Column '{column_name}' type mismatch: "
                        f"expected {expected_type}, got {actual_type_name}"
                    )
            else:
                # Direct string comparison for custom types
                if expected_type_lower not in actual_type_name:
                    errors.append(
                        f"Column '{column_name}' type mismatch: "
                        f"expected {expected_type}, got {actual_type_name}"
                    )
        else:
            # Handle DataType objects
            if not isinstance(field.dataType, type(expected_type)):
                errors.append(
                    f"Column '{column_name}' type mismatch: "
                    f"expected {expected_type}, got {field.dataType}"
                )

        return errors

    def _is_compatible_numeric_type(self, expected: str, actual: str) -> bool:
        """Check if numeric types are compatible."""
        # Define compatible numeric type groups
        integer_types = {"int", "integer", "long", "bigint"}
        float_types = {"float", "double"}

        expected_lower = expected.lower()

        # Check integer compatibility
        if expected_lower in integer_types:
            return any(int_type in actual for int_type in ["int", "long", "bigint"])

        # Check float compatibility
        if expected_lower in float_types:
            return any(float_type in actual for float_type in ["float", "double"])

        return False

    def _validate_column_count(self, df: DataFrame, schema: dict) -> List[str]:
        """Validate column count constraints."""
        errors = []

        # Handle None DataFrame
        if df is None:
            return errors

        column_count = len(df.columns)

        if "min_columns" in schema:
            min_cols = schema["min_columns"]
            if column_count < min_cols:
                errors.append(
                    f"Too few columns: expected at least {min_cols}, got {column_count}"
                )

        if "max_columns" in schema:
            max_cols = schema["max_columns"]
            if column_count > max_cols:
                errors.append(
                    f"Too many columns: expected at most {max_cols}, got {column_count}"
                )

        return errors

    def _validate_strict_mode(self, df: DataFrame, schema: dict) -> List[str]:
        """Validate strict mode - no extra columns allowed."""
        errors = []

        # Handle None DataFrame or missing columns schema
        if df is None or "columns" not in schema:
            return errors

        expected_columns = set(schema["columns"].keys())
        actual_columns = set(df.columns)

        extra_columns = actual_columns - expected_columns
        if extra_columns:
            errors.append(f"Unexpected columns in strict mode: {sorted(extra_columns)}")

        return errors

    def get_schema_summary(self, df: DataFrame) -> dict:
        """Get a summary of the DataFrame schema for debugging."""
        if not PYSPARK_AVAILABLE:
            return {"error": "PySpark is not available"}

        if df is None:
            return {"error": "DataFrame is None"}

        try:
            summary = {"column_count": len(df.columns), "columns": {}}

            for field in df.schema.fields:
                summary["columns"][field.name] = {
                    "type": field.dataType.simpleString(),
                    "nullable": field.nullable,
                }

            return summary
        except Exception as e:
            return {"error": f"Failed to get schema summary: {str(e)}"}

    def create_schema_from_dataframe(self, df: DataFrame, strict: bool = False) -> dict:
        """Create a schema definition from an existing DataFrame."""
        if not PYSPARK_AVAILABLE:
            raise ImportError(
                "PySpark is required for DataFrame operations but is not installed"
            )

        if df is None:
            raise ValueError("DataFrame is None")

        schema = {"columns": {}, "strict": strict}

        for field in df.schema.fields:
            # Map Spark types back to simple type names
            spark_type = field.dataType.simpleString().lower()
            simple_type = self._spark_type_to_simple(spark_type)

            schema["columns"][field.name] = {
                "type": simple_type,
                "nullable": field.nullable,
                "required": True,
            }

        return schema

    def _spark_type_to_simple(self, spark_type: str) -> str:
        """Convert Spark type string to simple type name."""
        spark_type_lower = spark_type.lower()

        # Use centralized reverse mapping
        for spark_t, simple_t in self.SPARK_TO_TYPE_MAPPING.items():
            if spark_t in spark_type_lower:
                return simple_t

        # Return original if no mapping found
        return spark_type
