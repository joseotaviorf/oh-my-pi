class TableFormatInfo:
    """
    Maps the parameters related to the table storage for the Hive Metastore
     according to the file type.
    """

    def __init__(self, serde_lib=None, input_format=None, output_format=None) -> None:
        """
        Constructor.

        You should use this class through the properties:
         TableFormatInfo().parquet() or TableFormatInfo().json()

        :param input_format: SequenceFileInputFormat (binary) or
        TextInputFormat or custom format
        :param output_format: SequenceFileOutputFormat (binary) or
        IgnoreKeyTextOutputFormat or custom format
        :param serde_lib: the serialization class
        """
        self.serde_lib = serde_lib
        self.input_format = input_format
        self.output_format = output_format

    @property
    def parquet(self):
        """Maps the parameters for the table definition based on parquet files."""
        self.serde_lib = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
        self.input_format = (
            "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
        )
        self.output_format = (
            "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"
        )
        return self

    @property
    def json(self):
        """Maps the parameters for the table definition based on json files."""
        self.serde_lib = "org.apache.hive.hcatalog.data.JsonSerDe"
        self.input_format = "org.apache.hadoop.mapred.TextInputFormat"
        self.output_format = "org.apache.hadoop.hive.ql.io.IgnoreKeyTextOutputFormat"
        return self
