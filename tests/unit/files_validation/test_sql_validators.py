import pytest


class TestSqlFileValidators:
    """
    Test SQL validators
    """

    @pytest.mark.parametrize(
        "query_content, required_columns",
        [
            (
                [
                    "select distinct ",
                    "m.date as sk_date, ",
                    "coalesce(m.city_group) as city_group, ",
                    " share from mock_table m where m.date = 2020-01-01",
                ],
                ["sk_date", "city_group", "share"],
            )
        ],
    )
    def test_validate_sql_columns(
        self, query_content, required_columns, sql_validator_mock
    ):
        """
        Tests if validate_sql_columns returns True given correct query compared with required columns
        """
        assert sql_validator_mock.validate_sql_columns(query_content, required_columns)

    @pytest.mark.parametrize(
        "query_content, required_columns",
        [
            (
                [
                    "select distinct ",
                    "m.date, ",
                    "coalesce(m.city_group), ",
                    "value as share from mock_table m where m.date = 2020-01-01",
                ],
                ["sk_date", "city_group", "share"],
            )
        ],
    )
    def test_wrong_sql_columns(
        self, query_content, required_columns, sql_validator_mock
    ):
        """
        Tests if validate_sql_columns returns False given wrong query compared with required columns
        """
        assert (
            sql_validator_mock.validate_sql_columns(query_content, required_columns)
            is False
        )
