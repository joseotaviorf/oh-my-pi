import sys
import unittest
from unittest.mock import MagicMock

sys.modules["pyspark"] = MagicMock()
sys.modules["pyspark.conf"] = MagicMock()
sys.modules["pyspark.sql"] = MagicMock()
sys.modules["pyspark.sql.functions"] = MagicMock()
sys.modules["pyspark.sql.types"] = MagicMock()
sys.modules["pyspark.sql.dataframe"] = MagicMock()
sys.modules["pyspark.context"] = MagicMock()

sys.modules["quintoandar_logger"] = MagicMock()
sys.modules["bietlejuice.services.metastore_services"] = MagicMock()
sys.modules["bietlejuice.services.configuration_service"] = MagicMock()
sys.modules["bietlejuice.loaders"] = MagicMock()
sys.modules["bietlejuice.loaders.s3_loader"] = MagicMock()
sys.modules["bietlejuice.clients.db_clients"] = MagicMock()
sys.modules["bietlejuice.base.db"] = MagicMock()
sys.modules["bietlejuice.base.spark"] = MagicMock()
sys.modules["bietlejuice.base.validation"] = MagicMock()
sys.modules["bietlejuice.base.validation.spark_args"] = MagicMock()

from dags.governance.inmetro.spark_jobs.load_inmetro_raw import _generate_date_range  # noqa: E402, I001


class TestGenerateDateRange(unittest.TestCase):
    def test_single_day_returns_one_date(self):
        result = _generate_date_range("2024-01-01", "2024-01-01")
        self.assertEqual(result, ["2024-01-01"])

    def test_two_consecutive_days(self):
        result = _generate_date_range("2024-01-01", "2024-01-02")
        self.assertEqual(result, ["2024-01-01", "2024-01-02"])

    def test_week_range_returns_seven_dates(self):
        result = _generate_date_range("2024-03-01", "2024-03-07")
        self.assertEqual(len(result), 7)
        self.assertEqual(result[0], "2024-03-01")
        self.assertEqual(result[-1], "2024-03-07")

    def test_month_boundary(self):
        result = _generate_date_range("2024-01-31", "2024-02-01")
        self.assertEqual(result, ["2024-01-31", "2024-02-01"])

    def test_inverted_range_raises_value_error(self):
        with self.assertRaises(ValueError) as ctx:
            _generate_date_range("2024-01-05", "2024-01-01")
        self.assertIn("load_start_date", str(ctx.exception))

    def test_dates_are_formatted_as_yyyy_mm_dd(self):
        result = _generate_date_range("2024-06-09", "2024-06-11")
        for date in result:
            self.assertRegex(date, r"^\d{4}-\d{2}-\d{2}$")
