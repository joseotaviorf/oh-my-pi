import pytest

from bietlejuice.jobs.composer.base.spark import BaseSparkContext

spark, sc = BaseSparkContext.spark, BaseSparkContext.sc


class TestDataframeService:
    def test_format_column_names(self, dataframe_service):
        # arrange
        input_col_names = ["Abb", "ab", "abc cba", "Abc abc", "abc.abc", "Abc.abc abc"]
        expected_col_names = [
            "_abb",
            "ab",
            "abc_cba",
            "_abc_abc",
            "abc_abc",
            "_abc_abc_abc",
        ]

        data = [{k: 1 for k in input_col_names}]
        df = spark.read.json(sc.parallelize(data, 1))
        df.show()

        # act
        df = dataframe_service.input(df).format_column_names().output()
        result_col_names = df.schema.fieldNames()

        # assert
        assert result_col_names.sort() == expected_col_names.sort()

    @pytest.mark.parametrize(
        "data, expected_dtypes",
        [
            ([{"a": {"b": 1, "c": 2}, "d": 3}], [("a", "string"), ("d", "bigint")]),
            ([{"a": 1, "d": 3}], [("a", "bigint"), ("d", "bigint")]),
        ],
    )
    def test_convert_struct_type_to_json(self, data, expected_dtypes, dataframe_service):
        # arrange
        df = spark.read.json(sc.parallelize(data, 1))

        # act
        result_dtypes = (
            dataframe_service.input(df).convert_struct_type_to_json().output().dtypes
        )

        # assert
        assert result_dtypes == expected_dtypes

    def test_convert_struct_type_to_json_invalid_params(self, dataframe_service):
        # arrange
        df = None

        # assert
        with pytest.raises(ValueError) as ae:
            assert dataframe_service.input(df).convert_struct_type_to_json().output()

    @pytest.mark.parametrize(
        "data, expected_cols",
        [
            (
                [{"json": {"abc.abc": 1, "abc Cba": 2}, "d": 3}],
                ["json_abc_abc", "json_abc__cba", "d"],
            ),
            ([{"json": "", "d": 3}], ["d"]),
        ],
    )
    def test_explode_json_column(self, data, expected_cols, dataframe_service):
        # arrange
        df = spark.read.json(sc.parallelize(data, 1))

        # act
        df = (
            dataframe_service.input(df)
            .convert_struct_type_to_json()
            .explode_json_column("json", prefix="json_", format_column_names=True)
            .output()
        )
        result_cols = df.schema.fieldNames()

        # assert
        assert result_cols.sort() == expected_cols.sort()

    @pytest.mark.parametrize(
        "df", [spark.read.json(sc.parallelize([{"a": 1, "b": 2}], 1)), None]
    )
    def test_explode_json_column_invalid_params(self, df, dataframe_service):
        # assert
        with pytest.raises(ValueError) as ae:
            assert dataframe_service.input(df).explode_json_column("json").output()

    @pytest.mark.parametrize(
        "records, records_by_partition",
        [(10000, 10), (10000, 100), (0, 1), (10000, 5000)],
    )
    def test_optimize_partition(self, records, records_by_partition, dataframe_service):
        # arrange
        data = [{"a": "abc"}] * records
        df = spark.read.json(sc.parallelize(data))
        expected_partitions = max(records // records_by_partition, 1)
        # act
        df = (
            dataframe_service.input(df)
            .optimize_partition(records_by_partition)
            .output()
        )

        # assert
        assert expected_partitions == df.rdd.getNumPartitions()

    @pytest.mark.parametrize(
        "records, records_by_partition",
        [(10000, 10), (10000, 100), (0, 1), (10000, 5000)],
    )
    def test_optimize_partition(self, records, records_by_partition, dataframe_service):
        # arrange
        data = [{"a": "abc"}] * records
        df = spark.read.json(sc.parallelize(data))
        expected_partitions = max(records // records_by_partition, 1)
        # act
        df = (
            dataframe_service.input(df)
            .optimize_partition(records_by_partition)
            .output()
        )

        # assert
        assert expected_partitions == df.rdd.getNumPartitions()