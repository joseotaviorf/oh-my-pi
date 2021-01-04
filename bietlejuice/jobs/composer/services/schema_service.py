from collections import OrderedDict


class SchemaService:
    @staticmethod
    def get_schema_from_dataframe(dataframe):
        """
        Returns the dataframe's schema as a dict that specifies the name and type
        for each column (including partitioning columns).

        :param dataframe: dataframe to get schema from.
        :type dataframe: pyspark.sql.DataFrame
        :return: OrderedDict with schema
        """
        schema_df = OrderedDict(
            field.simpleString().split(":", 1) for field in dataframe.schema.fields
        )
        return schema_df

    @staticmethod
    def get_schema_from_dataframe_as_string(dataframe):
        """
        Returns the dataframe's schema as a string that specifies the name and type
        for each column (including partitioning columns).

        :param dataframe: dataframe to get schema from.
        :type dataframe: pyspark.sql.DataFrame
        :return: DDL-formatted string , e.g: col1 string,col2 int,col3 bigint
        """
        schema_df = ""
        for field in dataframe.schema.fields:
            col, col_type = field.simpleString().split(":", 1)
            schema_df += f"{col} {col_type},"
        schema_df = schema_df[:-1]

        return schema_df
