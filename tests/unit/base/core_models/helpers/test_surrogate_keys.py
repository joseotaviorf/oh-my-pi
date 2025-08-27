import pytest
from pyspark.sql import DataFrame
from pyspark.sql.types import StructType, StructField, StringType, IntegerType

from bietlejuice.base.core_models.helpers.surrogate_keys import SurrogateKeysHelper


class TestSurrogateKeysHelper:
    """Test cases for SurrogateKeysHelper class."""

    def test_generate_surrogate_key_basic_functionality(self, sample_dataframe):
        """Test basic surrogate key generation with default parameters."""
        # Arrange
        entity_type = "VISIT"

        # Act
        result_df = SurrogateKeysHelper.generate_surrogate_key(
            sample_dataframe, entity_type
        )

        # Assert
        assert "surrogate_key" in result_df.columns
        assert result_df.count() == 3

        # Verify surrogate keys are generated (not null)
        surrogate_keys = result_df.select("surrogate_key").collect()
        for row in surrogate_keys:
            assert row["surrogate_key"] is not None
            assert (
                len(row["surrogate_key"]) == 64
            )  # SHA256 produces 64-character hex string

    def test_generate_surrogate_key_with_custom_id_column(self, spark_session):
        """Test surrogate key generation with custom ID column name."""
        # Arrange
        schema = StructType(
            [
                StructField("custom_id", StringType(), True),
                StructField("name", StringType(), True),
            ]
        )
        data = [("abc123", "test_name")]
        df = spark_session.createDataFrame(data, schema)
        entity_type = "OFFER"

        # Act
        result_df = SurrogateKeysHelper.generate_surrogate_key(
            df, entity_type, id_column="custom_id"
        )

        # Assert
        assert "surrogate_key" in result_df.columns
        assert result_df.count() == 1

        # Verify the surrogate key is generated
        surrogate_key = result_df.select("surrogate_key").collect()[0]["surrogate_key"]
        assert surrogate_key is not None
        assert len(surrogate_key) == 64

    def test_generate_surrogate_key_deterministic_output(self, spark_session):
        """Test that the same input produces the same surrogate key."""
        # Arrange
        schema = StructType(
            [
                StructField("id_entity", StringType(), True),
                StructField("name", StringType(), True),
            ]
        )
        data = [("test_id", "test_name")]
        df = spark_session.createDataFrame(data, schema)
        entity_type = "CONTRACT"

        # Act - Generate surrogate key twice
        result_df1 = SurrogateKeysHelper.generate_surrogate_key(df, entity_type)
        result_df2 = SurrogateKeysHelper.generate_surrogate_key(df, entity_type)

        # Assert
        key1 = result_df1.select("surrogate_key").collect()[0]["surrogate_key"]
        key2 = result_df2.select("surrogate_key").collect()[0]["surrogate_key"]
        assert key1 == key2

    def test_generate_surrogate_key_different_entity_types_produce_different_keys(
        self, spark_session
    ):
        """Test that different entity types produce different surrogate keys for the same ID."""
        # Arrange
        schema = StructType(
            [
                StructField("id_entity", StringType(), True),
                StructField("name", StringType(), True),
            ]
        )
        data = [("same_id", "test_name")]
        df = spark_session.createDataFrame(data, schema)

        # Act
        result_visit = SurrogateKeysHelper.generate_surrogate_key(df, "VISIT")
        result_offer = SurrogateKeysHelper.generate_surrogate_key(df, "OFFER")

        # Assert
        key_visit = result_visit.select("surrogate_key").collect()[0]["surrogate_key"]
        key_offer = result_offer.select("surrogate_key").collect()[0]["surrogate_key"]
        assert key_visit != key_offer

    def test_generate_surrogate_key_different_ids_produce_different_keys(
        self, spark_session
    ):
        """Test that different IDs produce different surrogate keys for the same entity type."""
        # Arrange
        schema = StructType(
            [
                StructField("id_entity", StringType(), True),
                StructField("name", StringType(), True),
            ]
        )
        data = [("id_1", "name_1"), ("id_2", "name_2")]
        df = spark_session.createDataFrame(data, schema)
        entity_type = "VISIT"

        # Act
        result_df = SurrogateKeysHelper.generate_surrogate_key(df, entity_type)

        # Assert
        keys = result_df.select("surrogate_key").collect()
        key1 = keys[0]["surrogate_key"]
        key2 = keys[1]["surrogate_key"]
        assert key1 != key2

    def test_generate_surrogate_key_preserves_original_columns(self, sample_dataframe):
        """Test that original DataFrame columns are preserved."""
        # Arrange
        original_columns = sample_dataframe.columns
        entity_type = "VISIT"

        # Act
        result_df = SurrogateKeysHelper.generate_surrogate_key(
            sample_dataframe, entity_type
        )

        # Assert
        for col_name in original_columns:
            assert col_name in result_df.columns

        # Verify data integrity
        original_count = sample_dataframe.count()
        result_count = result_df.count()
        assert original_count == result_count

    def test_generate_surrogate_key_with_empty_dataframe(self, empty_dataframe):
        """Test surrogate key generation with empty DataFrame."""
        # Arrange
        entity_type = "VISIT"

        # Act
        result_df = SurrogateKeysHelper.generate_surrogate_key(
            empty_dataframe, entity_type
        )

        # Assert
        assert "surrogate_key" in result_df.columns
        assert result_df.count() == 0

    def test_generate_surrogate_key_with_null_id_values(self, spark_session):
        """Test surrogate key generation with null ID values."""
        # Arrange
        schema = StructType(
            [
                StructField("id_entity", StringType(), True),
                StructField("name", StringType(), True),
            ]
        )
        data = [(None, "test_name"), ("valid_id", "another_name")]
        df = spark_session.createDataFrame(data, schema)
        entity_type = "VISIT"

        # Act
        result_df = SurrogateKeysHelper.generate_surrogate_key(df, entity_type)

        # Assert
        assert "surrogate_key" in result_df.columns
        assert result_df.count() == 2

        # Check that surrogate keys are generated even for null IDs
        surrogate_keys = result_df.select("surrogate_key").collect()
        for row in surrogate_keys:
            assert row["surrogate_key"] is not None
            assert len(row["surrogate_key"]) == 64

    def test_generate_surrogate_key_with_special_characters_in_id(self, spark_session):
        """Test surrogate key generation with special characters in ID."""
        # Arrange
        schema = StructType(
            [
                StructField("id_entity", StringType(), True),
                StructField("name", StringType(), True),
            ]
        )
        data = [("id@#$%^&*()", "test_name"), ("id||with||pipes", "another_name")]
        df = spark_session.createDataFrame(data, schema)
        entity_type = "VISIT"

        # Act
        result_df = SurrogateKeysHelper.generate_surrogate_key(df, entity_type)

        # Assert
        assert "surrogate_key" in result_df.columns
        assert result_df.count() == 2

        # Verify surrogate keys are generated
        surrogate_keys = result_df.select("surrogate_key").collect()
        for row in surrogate_keys:
            assert row["surrogate_key"] is not None
            assert len(row["surrogate_key"]) == 64

    def test_generate_surrogate_key_return_type(self, sample_dataframe):
        """Test that the method returns a DataFrame."""
        # Arrange
        entity_type = "VISIT"

        # Act
        result = SurrogateKeysHelper.generate_surrogate_key(
            sample_dataframe, entity_type
        )

        # Assert
        assert isinstance(result, DataFrame)

    def test_generate_surrogate_key_with_numeric_id_column(self, spark_session):
        """Test surrogate key generation when ID column is numeric."""
        # Arrange
        schema = StructType(
            [
                StructField("id_entity", IntegerType(), True),
                StructField("name", StringType(), True),
            ]
        )
        data = [(123, "test_name"), (456, "another_name")]
        df = spark_session.createDataFrame(data, schema)
        entity_type = "VISIT"

        # Act
        result_df = SurrogateKeysHelper.generate_surrogate_key(df, entity_type)

        # Assert
        assert "surrogate_key" in result_df.columns
        assert result_df.count() == 2

        # Verify surrogate keys are generated
        surrogate_keys = result_df.select("surrogate_key").collect()
        for row in surrogate_keys:
            assert row["surrogate_key"] is not None
            assert len(row["surrogate_key"]) == 64

    def test_generate_surrogate_key_expected_hash_format(self, spark_session):
        """Test that generated surrogate key follows expected SHA256 hash format."""
        # Arrange
        schema = StructType(
            [
                StructField("id_entity", StringType(), True),
                StructField("name", StringType(), True),
            ]
        )
        data = [("test_id", "test_name")]
        df = spark_session.createDataFrame(data, schema)
        entity_type = "VISIT"

        # Act
        result_df = SurrogateKeysHelper.generate_surrogate_key(df, entity_type)

        # Assert
        surrogate_key = result_df.select("surrogate_key").collect()[0]["surrogate_key"]

        # SHA256 hash should be 64 characters long and contain only hexadecimal characters
        assert len(surrogate_key) == 64
        assert all(c in "0123456789abcdef" for c in surrogate_key.lower())

    def test_generate_surrogate_key_with_multiple_columns_list(self, spark_session):
        """Test surrogate key generation with multiple columns as list."""
        # Arrange
        schema = StructType(
            [
                StructField("id1", StringType(), True),
                StructField("id2", StringType(), True),
                StructField("name", StringType(), True),
            ]
        )
        data = [("abc", "123", "test_name")]
        df = spark_session.createDataFrame(data, schema)
        entity_type = "VISIT"

        # Act
        result_df = SurrogateKeysHelper.generate_surrogate_key(
            df, entity_type, id_column=["id1", "id2"]
        )

        # Assert
        assert "surrogate_key" in result_df.columns
        assert result_df.count() == 1

        # Verify the surrogate key is generated
        surrogate_key = result_df.select("surrogate_key").collect()[0]["surrogate_key"]
        assert surrogate_key is not None
        assert len(surrogate_key) == 64

    def test_generate_surrogate_key_multiple_columns_vs_single_column_different(
        self, spark_session
    ):
        """Test that multiple columns produce different keys than single columns."""
        # Arrange
        schema = StructType(
            [
                StructField("id1", StringType(), True),
                StructField("id2", StringType(), True),
                StructField("name", StringType(), True),
            ]
        )
        data = [("abc", "123", "test_name")]
        df = spark_session.createDataFrame(data, schema)
        entity_type = "VISIT"

        # Act
        result_single = SurrogateKeysHelper.generate_surrogate_key(
            df, entity_type, id_column="id1"
        )
        result_multiple = SurrogateKeysHelper.generate_surrogate_key(
            df, entity_type, id_column=["id1", "id2"]
        )

        # Assert
        key_single = result_single.select("surrogate_key").collect()[0]["surrogate_key"]
        key_multiple = result_multiple.select("surrogate_key").collect()[0][
            "surrogate_key"
        ]
        assert key_single != key_multiple

    def test_generate_surrogate_key_multiple_columns_deterministic(self, spark_session):
        """Test that multiple columns produce deterministic results."""
        # Arrange
        schema = StructType(
            [
                StructField("id1", StringType(), True),
                StructField("id2", StringType(), True),
                StructField("id3", StringType(), True),
                StructField("name", StringType(), True),
            ]
        )
        data = [("abc", "123", "xyz", "test_name")]
        df = spark_session.createDataFrame(data, schema)
        entity_type = "VISIT"

        # Act - Generate surrogate key twice with same columns
        result_df1 = SurrogateKeysHelper.generate_surrogate_key(
            df, entity_type, id_column=["id1", "id2", "id3"]
        )
        result_df2 = SurrogateKeysHelper.generate_surrogate_key(
            df, entity_type, id_column=["id1", "id2", "id3"]
        )

        # Assert
        key1 = result_df1.select("surrogate_key").collect()[0]["surrogate_key"]
        key2 = result_df2.select("surrogate_key").collect()[0]["surrogate_key"]
        assert key1 == key2

    def test_generate_surrogate_key_multiple_columns_order_matters(self, spark_session):
        """Test that the order of columns in the list affects the surrogate key."""
        # Arrange
        schema = StructType(
            [
                StructField("id1", StringType(), True),
                StructField("id2", StringType(), True),
                StructField("name", StringType(), True),
            ]
        )
        data = [("abc", "123", "test_name")]
        df = spark_session.createDataFrame(data, schema)
        entity_type = "VISIT"

        # Act
        result_order1 = SurrogateKeysHelper.generate_surrogate_key(
            df, entity_type, id_column=["id1", "id2"]
        )
        result_order2 = SurrogateKeysHelper.generate_surrogate_key(
            df, entity_type, id_column=["id2", "id1"]
        )

        # Assert
        key_order1 = result_order1.select("surrogate_key").collect()[0]["surrogate_key"]
        key_order2 = result_order2.select("surrogate_key").collect()[0]["surrogate_key"]
        assert key_order1 != key_order2

    def test_generate_surrogate_key_multiple_columns_with_nulls(self, spark_session):
        """Test surrogate key generation with multiple columns containing nulls."""
        # Arrange
        schema = StructType(
            [
                StructField("id1", StringType(), True),
                StructField("id2", StringType(), True),
                StructField("name", StringType(), True),
            ]
        )
        data = [(None, "123", "test_name"), ("abc", None, "another_name")]
        df = spark_session.createDataFrame(data, schema)
        entity_type = "VISIT"

        # Act
        result_df = SurrogateKeysHelper.generate_surrogate_key(
            df, entity_type, id_column=["id1", "id2"]
        )

        # Assert
        assert "surrogate_key" in result_df.columns
        assert result_df.count() == 2

        # Check that surrogate keys are generated even with null values
        surrogate_keys = result_df.select("surrogate_key").collect()
        for row in surrogate_keys:
            assert row["surrogate_key"] is not None
            assert len(row["surrogate_key"]) == 64

    def test_generate_surrogate_key_multiple_columns_different_data_types(
        self, spark_session
    ):
        """Test surrogate key generation with multiple columns of different data types."""
        # Arrange
        schema = StructType(
            [
                StructField("id_string", StringType(), True),
                StructField("id_int", IntegerType(), True),
                StructField("name", StringType(), True),
            ]
        )
        data = [("abc", 123, "test_name"), ("def", 456, "another_name")]
        df = spark_session.createDataFrame(data, schema)
        entity_type = "VISIT"

        # Act
        result_df = SurrogateKeysHelper.generate_surrogate_key(
            df, entity_type, id_column=["id_string", "id_int"]
        )

        # Assert
        assert "surrogate_key" in result_df.columns
        assert result_df.count() == 2

        # Verify surrogate keys are generated
        surrogate_keys = result_df.select("surrogate_key").collect()
        for row in surrogate_keys:
            assert row["surrogate_key"] is not None
            assert len(row["surrogate_key"]) == 64

        # Verify different rows produce different keys
        key1 = surrogate_keys[0]["surrogate_key"]
        key2 = surrogate_keys[1]["surrogate_key"]
        assert key1 != key2

    def test_generate_surrogate_key_single_column_as_list(self, spark_session):
        """Test that passing a single column as a list works the same as passing it as a string."""
        # Arrange
        schema = StructType(
            [
                StructField("id_entity", StringType(), True),
                StructField("name", StringType(), True),
            ]
        )
        data = [("test_id", "test_name")]
        df = spark_session.createDataFrame(data, schema)
        entity_type = "VISIT"

        # Act
        result_string = SurrogateKeysHelper.generate_surrogate_key(
            df, entity_type, id_column="id_entity"
        )
        result_list = SurrogateKeysHelper.generate_surrogate_key(
            df, entity_type, id_column=["id_entity"]
        )

        # Assert
        key_string = result_string.select("surrogate_key").collect()[0]["surrogate_key"]
        key_list = result_list.select("surrogate_key").collect()[0]["surrogate_key"]
        assert key_string == key_list

    def test_generate_surrogate_key_empty_list_raises_error(self, spark_session):
        """Test that passing an empty list raises an error."""
        # Arrange
        schema = StructType(
            [
                StructField("id_entity", StringType(), True),
                StructField("name", StringType(), True),
            ]
        )
        data = [("test_id", "test_name")]
        df = spark_session.createDataFrame(data, schema)
        entity_type = "VISIT"

        # Act & Assert
        with pytest.raises(ValueError, match="id_column list cannot be empty"):
            SurrogateKeysHelper.generate_surrogate_key(df, entity_type, id_column=[])

    def test_generate_surrogate_key_invalid_type_raises_error(self, spark_session):
        """Test that passing an invalid type for id_column raises TypeError."""
        # Arrange
        schema = StructType(
            [
                StructField("id_entity", StringType(), True),
                StructField("name", StringType(), True),
            ]
        )
        data = [("test_id", "test_name")]
        df = spark_session.createDataFrame(data, schema)
        entity_type = "VISIT"

        # Act & Assert
        with pytest.raises(TypeError, match="id_column must be str or list of str"):
            SurrogateKeysHelper.generate_surrogate_key(df, entity_type, id_column=123)
