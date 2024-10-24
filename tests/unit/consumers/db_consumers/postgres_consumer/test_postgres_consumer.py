import textwrap
from unittest import mock
import pytest


class TestPostgresConsumer:
    @mock.patch(
        "bietlejuice.consumers.db_consumers.postgres_consumer.PostgresConsumer.get_data_from_query"
    )
    @pytest.mark.parametrize(
        "expression_params",
        [
            [
                {
                    "table_name": "tabela_dummy",
                    "date_filter_column": "ts_column",
                    "load_start_date": "2024-03-22",
                    "load_end_date": "2024-03-25",
                    "unixtime_measure": None,
                },
                """
            SELECT
                *,
                CAST(EXTRACT(YEAR FROM ts_column) as INT) AS year,
                CAST(EXTRACT(MONTH FROM ts_column) as INT) AS month,
                CAST(EXTRACT(DAY FROM ts_column) as INT) AS day
            FROM
                "public"."tabela_dummy"
            WHERE
                ts_column >= DATE('2024-03-22')
                AND ts_column < DATE(DATE('2024-03-25') + INTERVAL '1 DAY')
            """,
            ],
            [
                {
                    "table_name": "tabela_dummy",
                    "date_filter_column": "ts_column",
                    "load_start_date": "2024-03-25",
                    "load_end_date": "2024-03-25",
                    "unixtime_measure": "milliseconds",
                },
                """
            SELECT
                *,
                CAST(EXTRACT(YEAR FROM TO_TIMESTAMP(ts_column/1000)) as INT) AS year,
                CAST(EXTRACT(MONTH FROM TO_TIMESTAMP(ts_column/1000)) as INT) AS month,
                CAST(EXTRACT(DAY FROM TO_TIMESTAMP(ts_column/1000)) as INT) AS day
            FROM
                "public"."tabela_dummy"
            WHERE
                TO_TIMESTAMP(ts_column/1000) >= DATE('2024-03-25')
                AND TO_TIMESTAMP(ts_column/1000) < DATE(DATE('2024-03-25') + INTERVAL '1 DAY')
            """,
            ],
            [
                {
                    "table_name": "tabela_dummy",
                    "date_filter_column": "ts_column",
                    "load_start_date": "2024-03-25",
                    "load_end_date": "2024-03-25",
                    "unixtime_measure": "seconds",
                },
                """
            SELECT
                *,
                CAST(EXTRACT(YEAR FROM TO_TIMESTAMP(ts_column)) as INT) AS year,
                CAST(EXTRACT(MONTH FROM TO_TIMESTAMP(ts_column)) as INT) AS month,
                CAST(EXTRACT(DAY FROM TO_TIMESTAMP(ts_column)) as INT) AS day
            FROM
                "public"."tabela_dummy"
            WHERE
                TO_TIMESTAMP(ts_column) >= DATE('2024-03-25')
                AND TO_TIMESTAMP(ts_column) < DATE(DATE('2024-03-25') + INTERVAL '1 DAY')
            """,
            ],
        ],
    )
    def test_get_incremental_data_by_processing_window(
        self, mocked_get_data_from_query, expression_params, postgres_consumer
    ):
        print(len(expression_params))
        input_values = expression_params[0]
        output_value = textwrap.dedent(expression_params[1])
        postgres_consumer.get_incremental_data_by_processing_window(
            table_name=input_values["table_name"],
            date_filter_column=input_values["date_filter_column"],
            load_start_date=input_values["load_start_date"],
            load_end_date=input_values["load_end_date"],
            unixtime_measure=input_values["unixtime_measure"],
        )
        mocked_get_data_from_query.assert_called_once_with(output_value)

    @mock.patch(
        "bietlejuice.consumers.db_consumers.postgres_consumer.PostgresConsumer.get_data_from_query"
    )
    def test_get_table_schema(self, mocked_get_data_from_query, postgres_consumer):
        table_name = "tabela_dummy"
        postgres_consumer.get_table_schema(table_name)
        mocked_get_data_from_query.assert_called_once_with(
            textwrap.dedent(
                """
            SELECT
                column_name AS col_name,
                data_type AS col_type,
                COALESCE(character_maximum_length, numeric_precision) AS col_length,
                numeric_scale AS col_scale
            FROM
                information_schema.columns
            WHERE
                table_schema = 'public'
                AND table_name = 'tabela_dummy'
            """
            )
        )

    @mock.patch(
        "bietlejuice.consumers.db_consumers.postgres_consumer.PostgresConsumer.get_data_from_query"
    )
    def test_get_table_primary_keys(
        self, mocked_get_data_from_query, postgres_consumer
    ):
        table_name = "tabela_dummy"
        df_mock = mock.MagicMock()
        row_mock = mock.MagicMock()
        row_mock.col_name = "id"
        df_mock.collect.return_value = [row_mock]
        mocked_get_data_from_query.return_value = df_mock

        primary_keys = postgres_consumer.get_table_primary_keys(table_name)
        mocked_get_data_from_query.assert_called_once_with(
            textwrap.dedent(
                """
            SELECT
                a.attname as col_name
            FROM
                pg_index i
            JOIN
                pg_attribute a ON a.attrelid = i.indrelid
                AND a.attnum = ANY(i.indkey)
            WHERE
                i.indrelid = 'public."tabela_dummy"'::regclass
                AND i.indisprimary
        """
            )
        )

        assert primary_keys == ["id"]
