class SparkSQLCLient:
    def __init__(self, spark, sqlContext):
        self.spark = spark
        self.sqlContext = sqlContext

    def run(self, query):
        self.spark.sql(query)

    def table_names(self, db):
        return self.sqlContext.tableNames(dbName=db)

    def table(self, table_name):
        return self.sqlContext.table(table_name)
