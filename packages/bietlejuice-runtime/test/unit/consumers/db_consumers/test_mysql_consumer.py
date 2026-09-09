from unittest import mock

import pytest

from bietlejuice.consumers.db_consumers.mysql_consumer import MySqlConsumer


@pytest.fixture
def spark_client():
    client = mock.MagicMock()
    client.conn._jvm = mock.MagicMock()
    return client


@pytest.fixture
def mysql_consumer(spark_client):
    return MySqlConsumer(
        conn_config={
            "dbtype": "mysql",
            "host": "localhost",
            "port": "3306",
            "db": "database_name",
            "user": "database_user",
            "pwd": "database_password",
        },
        spark_client=spark_client,
    )


class TestMySqlConsumerDriverQueries:
    def test_get_driver_query_rows_executes_and_closes_jdbc_resources(
        self, mysql_consumer, spark_client
    ):
        # Arrange
        jvm = spark_client.conn._jvm
        connection = jvm.com.mysql.cj.jdbc.Driver.return_value.connect.return_value
        statement = connection.prepareStatement.return_value
        result_set = statement.executeQuery.return_value
        metadata = result_set.getMetaData.return_value
        metadata.getColumnCount.return_value = 2
        metadata.getColumnLabel.side_effect = {
            1: "col_name",
            2: "col_type",
        }.get
        result_set.next.side_effect = [True, False]
        result_set.getString.side_effect = {
            1: "id",
            2: "bigint",
        }.get

        # Act
        rows = mysql_consumer.get_driver_query_rows(
            "SELECT value FROM metadata WHERE schema_name = ?",
            ("database_name",),
        )

        # Assert
        assert rows == [{"col_name": "id", "col_type": "bigint"}]
        statement.setString.assert_called_once_with(1, "database_name")
        result_set.close.assert_called_once_with()
        statement.close.assert_called_once_with()
        connection.close.assert_called_once_with()

    @pytest.mark.parametrize(
        ("method_name", "expected_rows"),
        [
            (
                "get_table_schema_on_driver",
                [{"col_name": "id", "col_type": "bigint"}],
            ),
            ("get_table_primary_keys_on_driver", ["id"]),
        ],
    )
    def test_table_metadata_queries_run_on_driver(
        self, mysql_consumer, method_name, expected_rows
    ):
        # Arrange
        mysql_consumer.get_driver_query_rows = mock.MagicMock(
            return_value=[{"col_name": "id", "col_type": "bigint"}]
        )

        # Act
        result = getattr(mysql_consumer, method_name)("table_name")

        # Assert
        assert result == expected_rows
        query, parameters = mysql_consumer.get_driver_query_rows.call_args.args
        assert "INFORMATION_SCHEMA" in query
        assert parameters == ("database_name", "table_name")
