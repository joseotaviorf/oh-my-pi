from collections import OrderedDict


class SchemaService:
    @staticmethod
    def get_schema_from_dataframe(dataframe):
        """Returns the dataframe's schema as a dict that specifies the name and type
        for each column (including partitioning columns).
        :param dataframe: dataframe to get schema from.
        :return: OrderedDict with schema
        """
        df_schema = OrderedDict(
            field.simpleString().split(":", 1) for field in dataframe.schema.fields
        )
        return df_schema
