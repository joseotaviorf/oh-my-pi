"""Minimal EMR Spark sample: Pi estimation."""

from random import random
from operator import add

from pyspark.sql import SparkSession


def main() -> None:
    spark = SparkSession.builder.appName("EmrPocSamplePi").getOrCreate()
    sc = spark.sparkContext
    partitions = 2
    n = 100000 * partitions

    def inside(_: int) -> int:
        x, y = random(), random()
        return 1 if x * x + y * y <= 1 else 0

    count = (
        sc.parallelize(range(1, n + 1), partitions).map(inside).reduce(add)
    )
    pi = 4.0 * count / n
    print("Pi is roughly %f" % pi)
    spark.stop()


if __name__ == "__main__":
    main()
