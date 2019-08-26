class SparkSQLCLient:
    def __init__(self, spark):
        self.spark = spark

    def run(self, query):
        self.spark.sql(query)
