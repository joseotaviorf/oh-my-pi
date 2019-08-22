import pytest

from bietlejuice.jobs.composer.base.spark import BaseSparkContext

spark, sc = BaseSparkContext.spark, BaseSparkContext.sc

class TestDataframeService:
    def test_df_columns_name_format(self, dataframe_service):
        # arrange
        input_col_names = ['Abb', 'ab', 'abc cba', 'Abc abc', 'abc.abc', 'Abc.abc abc']
        expected_col_names = ['_abb', 'ab', 'abc_cba', '_abc_abc', 'abc_abc', '_abc_abc_abc']

        data = [{k: 1 for k in input_col_names}]
        df = spark.read.json(sc.parallelize(data, 1))
        df.show()

        # act
        df = dataframe_service.df_columns_name_format(df)
        result_col_names = df.schema.fieldNames()

        # assert
        assert result_col_names.sort() == expected_col_names.sort()

    @pytest.mark.parametrize('data, expected_dtypes', [
        ([{'a': {'b': 1, 'c':2}, 'd': 3}], [('a', 'string'), ('d', 'bigint')]),
        ([{'a': 1, 'd': 3}], [('a', 'bigint'), ('d', 'bigint')])
    ])
    def test_df_struct_type_to_json(self, data, expected_dtypes, dataframe_service):
        # arrange
        df = spark.read.json(sc.parallelize(data, 1))

        # act
        result_dtypes = dataframe_service.df_struct_type_to_json(df).dtypes

        # assert
        assert result_dtypes == expected_dtypes

    def test_df_struct_type_to_json_invalid_params(self, dataframe_service):
        # arrange
        df = None

        # assert
        with pytest.raises(AttributeError) as ae:
            assert dataframe_service.df_struct_type_to_json(df)

    @pytest.mark.parametrize('data, expected_cols', [
        ([{'json': {'abc.abc': 1, 'abc Cba': 2}, 'd': 3}], ['json_abc_abc', 'json_abc__cba', 'd']),
        ([{'json': '', 'd': 3}], ['d'])
    ])
    def test_explode_json_column(self, data, expected_cols, dataframe_service):
        # arrange
        df = spark.read.json(sc.parallelize(data, 1))

        # act
        df = dataframe_service.df_struct_type_to_json(df)
        df = dataframe_service.explode_json_column(df, 'json', prefix="json_", format_column_names=True)
        result_cols = df.schema.fieldNames()

        # assert
        assert result_cols.sort() == expected_cols.sort()

    def test_explode_json_column_invalid_params(self, dataframe_service):
        # arrange
        data = [{'a': 1, 'b': 2}]
        df1 = spark.read.json(sc.parallelize(data, 1))
        df2 = None

        # assert
        with pytest.raises(AttributeError) as ae:
            assert dataframe_service.explode_json_column(df1, 'json')

        with pytest.raises(AttributeError) as ae:
            assert dataframe_service.explode_json_column(df2, 'json')
