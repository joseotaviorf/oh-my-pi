class SparkSQLCLient:
    def __init__(self, spark, sqlContext):
        self.spark = spark
        self.sqlContext = sqlContext

    def run(self, query):
        return self.spark.sql(query)

    def get_table_names(self, db):
        return self.sqlContext.tableNames(dbName=db)

    def get_table(self, table_name):
        return self.sqlContext.table(table_name)
