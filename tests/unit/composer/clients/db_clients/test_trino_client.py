from mock import Mock
from trino import constants
from trino.dbapi import Connection

from bietlejuice.jobs.composer.clients.db_clients import TrinoClient


class TestTrinoClient:
    def test_conn(self):
        # arrange
        mocked_trino_client = TrinoClient(
            host="host", port=443, user="jose.silva", password="pwd"
        )

        # act
        conn = mocked_trino_client.conn

        # assert
        assert isinstance(conn, Connection)
        assert conn.catalog == "hive"
        assert conn.http_scheme == constants.HTTPS

    def test_get_records(self, mocked_trino_client):
        # arrange
        query = "select * from bla where x={}"
        parameters = ["foo"]

        expected_return = [("1", "2", "3")]

        mocked_trino_conn = Mock()

        mocked_cursor = Mock()
        mocked_cursor.fetchall.return_value = expected_return

        new_obj = Mock()
        new_obj.cursor.return_value = mocked_cursor

        mocked__enter__ = Mock()
        mocked__enter__.return_value = new_obj

        mocked_trino_conn.__enter__ = mocked__enter__
        mocked_trino_conn.__exit__ = Mock()

        mocked_trino_client.connection = mocked_trino_conn

        # act
        returned_value = mocked_trino_client.get_records(query, parameters)

        # assert
        assert returned_value == expected_return
        mocked_cursor.execute.assert_called_once_with(query, parameters)
        mocked_cursor.fetchall.assert_called_once_with()

    def test_run(self, mocked_trino_client):
        # arrange
        command = "drop table bla"
        parameters = ["foo"]

        mocked_cursor = Mock()
        new_obj = Mock()
        new_obj.cursor.return_value = mocked_cursor

        mocked__enter__ = Mock()
        mocked__enter__.return_value = new_obj

        mocked_trino_conn = Mock()
        mocked_trino_conn.__enter__ = mocked__enter__
        mocked_trino_conn.__exit__ = Mock()

        mocked_trino_client.connection = mocked_trino_conn

        # act
        mocked_trino_client.run(command, parameters)

        # assert
        mocked_cursor.execute.assert_called_once_with(command, parameters)
