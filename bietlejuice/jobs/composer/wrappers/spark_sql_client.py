class SparkSQLCLient:
    """
    This class is deprecated, and must be removed the sooner the better. Please
    use the SparkClient that is located in composer/clients/db_clients/spark_client.py
    """

    def __init__(self, spark, sqlContext):
        self.spark = spark
        self.sqlContext = sqlContext

    def run(self, query):
        return self.spark.sql(query)

    def get_table_names(self, db):
        return self.sqlContext.tableNames(dbName=db)

    def get_table(self, table_name):
        return self.sqlContext.table(table_name)
