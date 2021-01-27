import pytest
from pyspark import SparkContext
from pyspark.sql import session

from bietlejuice.jobs.composer.base.spark import SparkDataFrameService
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.etl.amplitude import AmplitudeEvents


class MockedSparkSqlConsumer:
    def __init__(self):
        self.result = None
        self.query_values = None

    def set_query_result(self, result):
        self.result = result

    def query_expected_values(self, values):
        self.query_values = values

    def get_data_from_query(self, query):
        if self.query_values:
            for value in self.query_values:
                if str(value) not in query:
                    raise ValueError(
                        "m=get_data_from_query, msg= key value={} not in query, "
                        "query={}".format(
                            value, query
                        )
                    )
        return self.result


@pytest.fixture()
def amplitude_events():
    return AmplitudeEvents(SparkClient())


@pytest.fixture()
def spark_sql_consumer():
    return MockedSparkSqlConsumer()


@pytest.fixture()
def dataframe_service():
    return SparkDataFrameService()


@pytest.fixture(scope='session')
def spark_context():
    spark_context = SparkContext.getOrCreate()
    yield spark_context
    spark_context.stop()


@pytest.fixture(scope='session')
def spark_session():
    spark_context = SparkContext.getOrCreate()
    yield session.SparkSession(spark_context)
    spark_context.stop()
