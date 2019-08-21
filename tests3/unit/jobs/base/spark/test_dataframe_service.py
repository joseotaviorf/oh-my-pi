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

    def test_df_struct_type_to_json(self, dataframe_service):
        # arrange
        df = spark.read.json(sc.parallelize([{'a': {'b': 1, 'c':2}, 'd':3}], 1))
        # input_dtypes = [('a', 'struct<b:bigint,c:bigint>'), ('d', 'bigint')]
        expected_dtypes = [('a', 'string'), ('d', 'bigint')]

        # act
        result_dtypes = dataframe_service.df_struct_type_to_json(df).dtypes

        # assert
        assert result_dtypes == expected_dtypes
