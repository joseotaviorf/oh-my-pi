"""Transform and main() tests for the monalisa_monitoria_evaluations custom spark job.

Run::

    uv run --directory packages/bietlejuice-runtime pytest \\
        test/dags/tech_platform/monalisa_monitoria_evaluations/spark_jobs/test_monalisa_monitoria_evaluations_load.py -q
"""

from argparse import Namespace
from datetime import date, datetime
from unittest.mock import MagicMock

import pytest

pytest.importorskip("pyspark")

from pyspark.sql.utils import AnalysisException  # noqa: E402

from dags.tech_platform.monalisa_monitoria_evaluations.spark_jobs import (  # noqa: E402
    monalisa_monitoria_evaluations_load as load_job,
)
from dags.tech_platform.monalisa_monitoria_evaluations.spark_jobs.monalisa_monitoria_evaluations_load import (  # noqa: E402
    _CRITERIA_TABLE,
    _HEADER_TABLE,
    _MERGE_ON,
    _NCGS_TABLE,
    EVALUATIONS_SCHEMA,
    base_df,
    criteria_df,
    deduplicate_latest_analysis,
    header_df,
    ncgs_df,
)

_MISSING_PATH = (
    "s3://monalisa-prod/evaluations/Monitoria/year=2026/month=07/day=21/*.ndjson.gz"
)

_PARTITION_DATE = date(2026, 7, 21)

# Two analyses of the SAME conversation (reference_id=100): a2 is newer (later ts_analysis) and
# must win the dedup; a distinct third conversation (200). Nested payload mirrors the producer.
_ROWS = [
    (
        "a1",
        100,
        "2026-07-21 08:00:00",
        "inbound",
        "resumo antigo",
        False,
        "ana@x.com",
        "fb antigo",
        "intent a1",
        "morno",
        ["pos-a1"],
        ["mel-a1"],
        (True, False, "Médio", "just a1"),
        [("Sondagem", "Conforme", "j-sond-a1"), ("Taxas", "Conforme", "j-tax-a1")],
        [("Divergência de Valores", "Conforme", "j-ncg-a1")],
    ),
    (
        "a2",
        100,
        "2026-07-21 12:00:00",
        "inbound",
        "resumo novo",
        True,
        "ana@x.com",
        "fb novo",
        "intent a2",
        "quente",
        ["pos-a2"],
        ["mel-a2"],
        (False, False, "Alto", "just a2"),
        [
            ("Sondagem", "Não conforme", "j-sond-a2"),
            ("Taxas", "Parcialmente Conforme", "j-tax-a2"),
        ],
        [("Divergência de Valores", "Não conforme", "j-ncg-a2")],
    ),
    (
        "b1",
        200,
        "2026-07-21 09:00:00",
        "carteirizacao",
        "resumo b",
        True,
        "bob@x.com",
        "fb b",
        "intent b1",
        "frio",
        ["pos-b1"],
        ["mel-b1"],
        (False, False, "Baixo", "just b1"),
        [("Fechamento", "Conforme", "j-fech-b1")],
        [("Divergência de Valores", "Conforme", "j-ncg-b1")],
    ),
]


@pytest.fixture()
def winning(spark):
    """base_df of the raw payload, deduplicated to the latest analysis per conversation."""
    raw = spark.createDataFrame(_ROWS, schema=EVALUATIONS_SCHEMA)
    return deduplicate_latest_analysis(base_df(raw, _PARTITION_DATE))


def test_merge_keys_are_reference_id_based():
    assert _MERGE_ON[_HEADER_TABLE] == ["id_reference"]
    assert _MERGE_ON[_CRITERIA_TABLE] == ["id_reference", "criterion"]
    assert _MERGE_ON[_NCGS_TABLE] == ["id_reference", "criterion"]


def test_dedup_keeps_latest_analysis_per_conversation(winning):
    rows = {r["id_reference"]: r for r in winning.collect()}
    assert set(rows) == {100, 200}
    # id_reference 100 was analyzed twice; the later ts_analysis (a2) must win.
    assert rows[100]["uuid_analysis"] == "a2"
    assert rows[200]["uuid_analysis"] == "b1"


def test_header_is_one_row_per_conversation_with_flattened_audio(winning):
    header = header_df(winning)
    assert set(header.columns) == {
        "id_reference",
        "uuid_analysis",
        "origin_flow",
        "summary",
        "email_primary_analyst",
        "feedback",
        "strengths",
        "improvement_areas",
        "client_intent_analysis",
        "lead_quality",
        "audio_confidence_level",
        "audio_inference_justification",
        "is_converted",
        "has_audio",
        "has_audio_impact",
        "ts_analysis",
        "year",
        "month",
        "day",
    }
    assert header.count() == 2
    row100 = header.filter(header.id_reference == 100).collect()[0]
    # Values come from the winning analysis (a2), not the stale one (a1).
    assert row100["summary"] == "resumo novo"
    assert row100["origin_flow"] == "inbound"
    assert row100["is_converted"] is True
    assert row100["has_audio"] is False
    assert row100["audio_confidence_level"] == "Alto"
    assert row100["client_intent_analysis"] == "intent a2"
    assert row100["lead_quality"] == "quente"
    assert row100["strengths"] == ["pos-a2"]
    assert row100["year"] == 2026 and row100["month"] == 7 and row100["day"] == 21


def test_criteria_explodes_checklist(winning):
    criteria = criteria_df(winning)
    assert set(criteria.columns) == {
        "id_reference",
        "criterion",
        "conformity",
        "justification",
        "year",
        "month",
        "day",
    }
    # 2 checklist items (winning a2) + 1 (b1) = 3 rows.
    assert criteria.count() == 3
    sond = criteria.filter(
        (criteria.id_reference == 100) & (criteria.criterion == "Sondagem")
    ).collect()
    assert len(sond) == 1
    # Proves the dedup fed the exploder the winning analysis (a2), not a1 ("Conforme").
    assert sond[0]["conformity"] == "Não conforme"


def test_ncgs_explodes_ncgs(winning):
    ncgs = ncgs_df(winning)
    assert set(ncgs.columns) == {
        "id_reference",
        "criterion",
        "conformity",
        "justification",
        "year",
        "month",
        "day",
    }
    # 1 NCG item per winning conversation (a2, b1) = 2 rows.
    assert ncgs.count() == 2
    ncg100 = ncgs.filter(ncgs.id_reference == 100).collect()[0]
    assert ncg100["criterion"] == "Divergência de Valores"
    assert ncg100["conformity"] == "Não conforme"


def _spark_failing_read(error_message):
    fake_spark = MagicMock()
    fake_spark.read.format.return_value.load.side_effect = AnalysisException(
        error_message
    )
    return fake_spark


@pytest.mark.parametrize(
    "error_message",
    [
        f"[PATH_NOT_FOUND] Path does not exist: {_MISSING_PATH}.",
        f"Path does not exist: {_MISSING_PATH}",
    ],
    ids=["databricks_error_class", "emr_plain_message"],
)
def test_missing_partition_returns_empty_frame(monkeypatch, error_message):
    """A day without evaluations must be a no-op on both Databricks and EMR wordings."""
    # Arrange
    fake_spark = _spark_failing_read(error_message)
    monkeypatch.setattr(load_job, "spark", fake_spark)

    # Act
    result = load_job.load_data_frame(_MISSING_PATH)

    # Assert
    assert result is fake_spark.createDataFrame.return_value
    fake_spark.createDataFrame.assert_called_once_with([], schema=EVALUATIONS_SCHEMA)


def test_unexpected_analysis_exception_propagates(monkeypatch):
    """Anything other than a missing path is a real error and must not read as no data."""
    # Arrange
    fake_spark = _spark_failing_read(
        "[UNRESOLVED_COLUMN] A column with name `x` cannot be resolved."
    )
    monkeypatch.setattr(load_job, "spark", fake_spark)

    # Act / Assert
    with pytest.raises(AnalysisException):
        load_job.load_data_frame(_MISSING_PATH)
    fake_spark.createDataFrame.assert_not_called()


_LAYER_DB = "datalake_tech_platform_clean"
_LAYER_LOCATION = "s3://5a-datalake-prod/clean/tech_platform"
_DEFAULT_WRITE_PATH = (
    "s3://5a-datalake-prod/clean/tech_platform/monalisa_monitoria_evaluations/"
)


def _monitoria_args(**overrides):
    args = Namespace(
        env="prod",
        datalake_bucket="5a-datalake-prod",
        schema="tech_platform",
        load_start_date=datetime(2026, 7, 21),
        load_end_date=datetime(2026, 7, 21),
        table_name=_HEADER_TABLE,
        partition_cols=["year", "month", "day"],
        target_database_name=None,
        target_table_name=None,
        path="s3://monalisa-prod/evaluations/Monitoria/{}/{}/{}/*.ndjson.gz",
    )
    for key, value in overrides.items():
        setattr(args, key, value)
    return args


def _stub_monitoria_pipeline(monkeypatch, *, records_count, clean_data_frame):
    raw_df = MagicMock(name="raw_df")
    raw_df.count.return_value = records_count
    transformed = MagicMock(name="transformed")
    transformed.dropDuplicates.return_value = clean_data_frame

    monkeypatch.setattr(load_job, "load_data_frame", lambda path: raw_df)
    monkeypatch.setattr(load_job, "base_df", lambda df, partition_date: MagicMock())
    monkeypatch.setattr(load_job, "deduplicate_latest_analysis", lambda df: MagicMock())
    monkeypatch.setitem(load_job._TRANSFORMS, _HEADER_TABLE, lambda df: transformed)
    load_job.DatalakeMetastoreService.get_layer_info.return_value = (
        _LAYER_DB,
        _LAYER_LOCATION,
        None,
    )
    return raw_df


class TestMainSecondaryCatalogSync:
    def test_syncs_after_delta_write_on_default_path(self, monkeypatch):
        # arrange
        args = _monitoria_args()
        clean_data_frame = MagicMock(name="clean_data_frame")
        clean_data_frame.columns = ["id_reference", "year", "month", "day"]
        monkeypatch.setattr(load_job, "parse_arguments", lambda: args)
        _stub_monitoria_pipeline(
            monkeypatch, records_count=2, clean_data_frame=clean_data_frame
        )

        loader = MagicMock()
        monkeypatch.setattr(load_job, "DeltaLoader", MagicMock(return_value=loader))
        mock_sync = MagicMock()
        mock_partitions = MagicMock(return_value=["year", "month", "day"])
        monkeypatch.setattr(
            load_job, "sync_delta_write_to_secondary_catalog", mock_sync
        )
        monkeypatch.setattr(load_job, "partition_columns_present", mock_partitions)

        call_order = []
        loader.load_table.side_effect = lambda **kwargs: call_order.append("load")
        mock_sync.side_effect = lambda *a, **k: call_order.append("sync")

        # act
        load_job.main()

        # assert
        loader.load_table.assert_called_once_with(
            table_name=f"{_LAYER_DB}.{_HEADER_TABLE}",
            path=_DEFAULT_WRITE_PATH,
            source_df=clean_data_frame,
            partition_by=args.partition_cols,
            merge_on=_MERGE_ON[_HEADER_TABLE],
        )
        mock_partitions.assert_called_once_with(clean_data_frame, args.partition_cols)
        mock_sync.assert_called_once_with(
            load_job.spark,
            f"{_LAYER_DB}.{_HEADER_TABLE}",
            _DEFAULT_WRITE_PATH,
            clean_data_frame,
            ["year", "month", "day"],
        )
        assert call_order == ["load", "sync"]

    def test_syncs_after_delta_write_on_validation_target(self, monkeypatch):
        # arrange
        args = _monitoria_args(
            target_database_name="cluster_validation",
            target_table_name="datalake_tech_platform_clean___monalisa_monitoria_evaluations",
        )
        clean_data_frame = MagicMock(name="clean_data_frame")
        monkeypatch.setattr(load_job, "parse_arguments", lambda: args)
        _stub_monitoria_pipeline(
            monkeypatch, records_count=1, clean_data_frame=clean_data_frame
        )

        write_location = "s3://5a-datalake-forno/cluster_validation/"
        expected_path = f"{write_location.rstrip('/')}/{args.target_table_name}"
        mock_resolve = MagicMock(
            return_value=(
                args.target_database_name,
                args.target_table_name,
                write_location,
            )
        )
        monkeypatch.setattr(load_job, "resolve_datalake_write_target", mock_resolve)

        loader = MagicMock()
        monkeypatch.setattr(load_job, "DeltaLoader", MagicMock(return_value=loader))
        mock_sync = MagicMock()
        mock_partitions = MagicMock(return_value=["year", "day"])
        monkeypatch.setattr(
            load_job, "sync_delta_write_to_secondary_catalog", mock_sync
        )
        monkeypatch.setattr(load_job, "partition_columns_present", mock_partitions)

        # act
        load_job.main()

        # assert
        mock_resolve.assert_called_once_with(
            prod_database=_LAYER_DB,
            prod_table=_HEADER_TABLE,
            prod_location=_LAYER_LOCATION,
            bucket=args.datalake_bucket,
            target_database=args.target_database_name,
            target_table=args.target_table_name,
        )
        loader.load_table.assert_called_once_with(
            table_name=f"{args.target_database_name}.{args.target_table_name}",
            path=expected_path,
            source_df=clean_data_frame,
            partition_by=args.partition_cols,
            merge_on=_MERGE_ON[_HEADER_TABLE],
        )
        mock_sync.assert_called_once_with(
            load_job.spark,
            f"{args.target_database_name}.{args.target_table_name}",
            expected_path,
            clean_data_frame,
            ["year", "day"],
        )

    def test_skips_sync_when_no_records_in_range(self, monkeypatch):
        # arrange
        args = _monitoria_args()
        monkeypatch.setattr(load_job, "parse_arguments", lambda: args)
        raw_df = MagicMock(name="raw_df")
        raw_df.count.return_value = 0
        monkeypatch.setattr(load_job, "load_data_frame", lambda path: raw_df)

        loader = MagicMock()
        monkeypatch.setattr(load_job, "DeltaLoader", MagicMock(return_value=loader))
        mock_sync = MagicMock()
        monkeypatch.setattr(
            load_job, "sync_delta_write_to_secondary_catalog", mock_sync
        )

        # act
        load_job.main()

        # assert
        loader.load_table.assert_not_called()
        mock_sync.assert_not_called()
