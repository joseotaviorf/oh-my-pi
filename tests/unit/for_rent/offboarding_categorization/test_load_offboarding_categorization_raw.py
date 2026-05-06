import sys
from unittest.mock import MagicMock

mock_pyspark = MagicMock()
sys.modules["pyspark"] = mock_pyspark
sys.modules["pyspark.sql"] = MagicMock()
sys.modules["pyspark.sql.functions"] = MagicMock()

sys.modules["bietlejuice.base.db"] = MagicMock()
sys.modules["bietlejuice.base.spark"] = MagicMock()
sys.modules["bietlejuice.clients.db_clients"] = MagicMock()
sys.modules["bietlejuice.consumers.s3_consumer"] = MagicMock()
sys.modules["bietlejuice.loaders"] = MagicMock()
sys.modules["bietlejuice.loaders.s3_loader"] = MagicMock()
sys.modules["bietlejuice.services.metastore_services"] = MagicMock()
sys.modules["quintoandar_logger"] = MagicMock()

from dags.for_rent.offboarding_categorization.spark_jobs.load_offboarding_categorization_raw import (  # noqa: E402
    build_session_metadata_parquet_uri,
    get_forno_adjusted_data_science_path,
)


def test_get_forno_adjusted_data_science_path_prod_unchanged():
    uri = "s3://data-science.s3.data.quintoandar.com.br/chatbot/x"
    assert get_forno_adjusted_data_science_path("prod", uri) == uri


def test_get_forno_adjusted_data_science_path_forno_swap():
    uri = "s3://data-science.s3.data.quintoandar.com.br/chatbot/x"
    assert (
        get_forno_adjusted_data_science_path("forno", uri)
        == "s3://data-science.s3.forno.data.quintoandar.com.br/chatbot/x"
    )


def test_build_session_metadata_parquet_uri():
    base = "s3://data-science.s3.data.quintoandar.com.br/chatbot/wall-e/session-metadata"
    assert (
        build_session_metadata_parquet_uri(base, "2026-03-11")
        == f"{base}/2026-03-11.parquet"
    )
    assert (
        build_session_metadata_parquet_uri(f"{base}/", "2026-03-11")
        == f"{base}/2026-03-11.parquet"
    )
