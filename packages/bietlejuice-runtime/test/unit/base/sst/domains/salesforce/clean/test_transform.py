"""Unit tests for the Salesforce CDC clean-layer conforming logic.

The clean-layer rule under test: for every column, a null in the incoming event
keeps the last known value and a non-null value overwrites it. Everything here is
about what "last" means, i.e. the ordering the carry-forward window replays in.
"""

import pytest
from pyspark.sql.types import (
    ArrayType,
    BooleanType,
    LongType,
    StringType,
    StructField,
    StructType,
)

from bietlejuice.base.sst.domains.salesforce.clean.transform import (
    BASELINE_COL,
    in_memory_cdc_udpate,
    search_for_latest_record,
)

# Mirrors the real events_case grain: identity + stream position + a sparse payload.
_SCHEMA = StructType(
    [
        StructField("id_record", StringType(), True),
        StructField("event_type", StringType(), True),
        StructField("transaction_key", StringType(), True),
        StructField("commit_number", LongType(), True),
        StructField("commit_ts", LongType(), True),
        StructField("sequence_number", LongType(), True),
        StructField("changed_field", ArrayType(StringType()), True),
        StructField("committed_at", StringType(), True),
        StructField("ownerid", StringType(), True),
        StructField("status", StringType(), True),
    ]
)

_BASELINE_SCHEMA = StructType(
    _SCHEMA.fields + [StructField(BASELINE_COL, BooleanType(), True)]
)

# The commit_ts second both 16:44:16 rows collide on in production.
_COLLIDING_TS = 1787762656000
_STREAM_COMMIT_NUMBER = 1787762656640368646

_REDUA = "005bL00000QJOyxQAH"
_SANTOS = "005bL00000QRPL7QAP"


def _event(
    event_type,
    commit_ts,
    commit_number,
    sequence_number,
    ownerid=None,
    status=None,
    changed_field=None,
    transaction_key=None,
    committed_at="2026-08-26 16:44:16",
    is_baseline=None,
):
    """One CDC row; `is_baseline` is only set for baseline-seeded scenarios."""
    row = (
        "500bL00000h5CkkQAE",
        event_type,
        transaction_key or f"tk-{commit_number}-{sequence_number}",
        commit_number,
        commit_ts,
        sequence_number,
        changed_field or [],
        committed_at,
        ownerid,
        status,
    )
    return row if is_baseline is None else row + (is_baseline,)


def _conform(spark_session, rows, schema=_SCHEMA):
    """Run the carry-forward and return rows keyed by commit_number."""
    df = spark_session.createDataFrame(rows, schema)
    return {
        row["commit_number"]: row
        for row in in_memory_cdc_udpate(df).orderBy("commit_ts").collect()
    }


class TestInMemoryCdcUpdate:
    def test_null_column_inherits_last_value_and_non_null_overwrites(
        self, spark_session
    ):
        # arrange: owner set once, then two sparse events, then a new owner
        rows = [
            _event("CREATE", 1000, 10, 1, ownerid=_SANTOS, status="Open"),
            _event("UPDATE", 2000, 20, 1, status="FS_IN_PROGRESS"),
            _event("UPDATE", 3000, 30, 1),
            _event("UPDATE", 4000, 40, 1, ownerid=_REDUA),
        ]

        # act
        result = _conform(spark_session, rows)

        # assert
        assert result[20]["ownerid"] == _SANTOS  # null -> keeps last
        assert result[20]["status"] == "FS_IN_PROGRESS"  # non-null -> overwrites
        assert result[30]["ownerid"] == _SANTOS
        assert result[30]["status"] == "FS_IN_PROGRESS"  # still carried
        assert result[40]["ownerid"] == _REDUA  # non-null -> overwrites
        assert result[40]["status"] == "FS_IN_PROGRESS"

    def test_snapshot_precedes_stream_event_sharing_its_commit_ts(self, spark_session):
        """The production defect: commit_ts has only second granularity, so a
        RECOVERY snapshot and a stream event collide on it. The snapshot must sort
        first so the sparse event inherits the recovered owner."""
        # arrange
        rows = [
            _event("CREATE", _COLLIDING_TS - 1000, 5, 1, ownerid=_SANTOS),
            # Snapshot carries the synthetic commit_number/sequence_number of 1.
            _event("RECOVERY", _COLLIDING_TS, 1, 1, ownerid=_REDUA, status="FS"),
            # Stream event in the same second; does not carry OwnerId.
            _event(
                "UPDATE",
                _COLLIDING_TS,
                _STREAM_COMMIT_NUMBER,
                2,
                changed_field=["LastModifiedDate"],
            ),
        ]

        # act
        result = _conform(spark_session, rows)

        # assert: both 16:44:16 rows agree on the recovered owner
        assert result[1]["ownerid"] == _REDUA
        assert result[_STREAM_COMMIT_NUMBER]["ownerid"] == _REDUA
        assert result[_STREAM_COMMIT_NUMBER]["status"] == "FS"

    def test_baseline_seeds_window_when_it_shares_the_new_event_commit_ts(
        self, spark_session
    ):
        """A baseline is a seed, not an event. If it were ordered by commit_ts, a
        stream event in the same second would sort first and be conformed against
        an empty window, nulling every column it does not carry."""
        # arrange
        rows = [
            _event(
                "HISTORICAL",
                _COLLIDING_TS,
                1,
                1,
                ownerid=_REDUA,
                status="FS",
                is_baseline=True,
            ),
            _event(
                "UPDATE",
                _COLLIDING_TS,
                _STREAM_COMMIT_NUMBER,
                2,
                is_baseline=False,
            ),
        ]

        # act
        result = _conform(spark_session, rows, _BASELINE_SCHEMA)

        # assert
        assert result[_STREAM_COMMIT_NUMBER]["ownerid"] == _REDUA
        assert result[_STREAM_COMMIT_NUMBER]["status"] == "FS"

    def test_baseline_column_is_not_emitted(self, spark_session):
        # arrange
        rows = [
            _event("HISTORICAL", 1000, 1, 1, ownerid=_SANTOS, is_baseline=True),
            _event("UPDATE", 2000, 20, 1, is_baseline=False),
        ]
        df = spark_session.createDataFrame(rows, _BASELINE_SCHEMA)

        # act
        result = in_memory_cdc_udpate(df)

        # assert: control columns stay internal and the output shape is unchanged
        # (identity + stream position first, then the carried payload columns)
        assert result.columns == [
            "id_record",
            "commit_number",
            "commit_ts",
            "sequence_number",
            "changed_field",
            "event_type",
            "transaction_key",
            "committed_at",
            "ownerid",
            "status",
        ]

    def test_orders_sequences_within_a_single_commit_number(self, spark_session):
        """One Salesforce commit can emit several events for the same record;
        sequence_number is the only key that separates them."""
        # arrange: same commit_number and commit_ts, ascending sequence
        rows = [
            _event("CREATE", 1000, 10, 1, ownerid=_SANTOS),
            _event("UPDATE", 2000, 20, 1, status="Open"),
            _event("UPDATE", 2000, 20, 2, status="AwaitingCustomer"),
            _event("UPDATE", 2000, 20, 3, ownerid=_REDUA),
        ]
        df = spark_session.createDataFrame(rows, _SCHEMA)

        # act
        result = {
            (row["commit_number"], row["sequence_number"]): row
            for row in in_memory_cdc_udpate(df).collect()
        }

        # assert
        assert result[(20, 1)]["status"] == "Open"
        assert result[(20, 2)]["status"] == "AwaitingCustomer"
        assert result[(20, 3)]["status"] == "AwaitingCustomer"  # carried
        assert result[(20, 3)]["ownerid"] == _REDUA

    def test_delete_nulls_payload_but_keeps_committed_at(self, spark_session):
        """committed_at is event metadata and must survive a DELETE. It was being
        nulled via a typo in the non-null list, which made a deleted row
        unselectable as the latest state."""
        # arrange
        rows = [
            _event("CREATE", 1000, 10, 1, ownerid=_SANTOS, status="Open"),
            _event("DELETE", 2000, 20, 1, committed_at="2026-08-26 16:50:00"),
        ]

        # act
        result = _conform(spark_session, rows)

        # assert
        assert result[20]["committed_at"] == "2026-08-26 16:50:00"
        assert result[20]["ownerid"] is None
        assert result[20]["status"] is None


def _incoming_sparse_update(spark_session):
    """A later sparse event with no CREATE, so the baseline lookup is triggered."""
    return spark_session.createDataFrame(
        [_event("UPDATE", 1787929179000, 1787929179993890819, 1, status="Awaiting")],
        _SCHEMA,
    )


class TestSearchForLatestRecord:
    @pytest.fixture
    def tied_commit_ts_table(self, spark_session):
        """Two stream events in the same second where sequence_number runs backwards
        against commit order — the shape seen in production (16:32:19 -> seq 4,
        16:44:16 -> seq 2). committed_at is identical, as it is derived from the
        already second-truncated commit_ts."""
        rows = [
            _event("CREATE", 1000, 10, 1, ownerid=_SANTOS, status="Open"),
            _event("UPDATE", _COLLIDING_TS, 100, 5, ownerid=_SANTOS, status="Open"),
            _event("UPDATE", _COLLIDING_TS, 200, 1, ownerid=_REDUA, status="Solved"),
        ]
        name = "test_clean_tied_commit_ts"
        spark_session.createDataFrame(rows, _SCHEMA).createOrReplaceTempView(name)
        return name

    @pytest.fixture
    def snapshot_is_latest_table(self, spark_session):
        """History whose most recent row is a RECOVERY snapshot, i.e. the row with
        the synthetic commit_number of 1 while the older stream event carries a
        real, far larger one."""
        rows = [
            _event("CREATE", 1000, 10, 1, ownerid=_SANTOS, status="Open"),
            _event("UPDATE", 2000, _STREAM_COMMIT_NUMBER, 4, status="FS"),
            _event("RECOVERY", 3000, 1, 1, ownerid=_REDUA, status="FS"),
        ]
        name = "test_clean_snapshot_is_latest"
        spark_session.createDataFrame(rows, _SCHEMA).createOrReplaceTempView(name)
        return name

    def test_breaks_commit_ts_tie_on_commit_number_not_sequence_number(
        self, spark_session, tied_commit_ts_table
    ):
        """The old sort was (committed_at, sequence_number) desc, so it handed the
        tie to the seq-5 row even though seq-1 has the later commit_number."""
        # arrange / act
        result = search_for_latest_record(
            spark_session, _incoming_sparse_update(spark_session), tied_commit_ts_table
        )
        baseline = [row for row in result.collect() if row[BASELINE_COL]]

        # assert
        assert len(baseline) == 1
        assert baseline[0]["status"] == "Solved"
        assert baseline[0]["ownerid"] == _REDUA

    def test_snapshot_wins_on_commit_ts_despite_its_commit_number_of_one(
        self, spark_session, snapshot_is_latest_table
    ):
        """commit_ts is the primary key, so a snapshot's synthetic commit_number of
        1 never drags it behind an older stream event."""
        # arrange / act
        result = search_for_latest_record(
            spark_session,
            _incoming_sparse_update(spark_session),
            snapshot_is_latest_table,
        )
        baseline = [row for row in result.collect() if row[BASELINE_COL]]

        # assert
        assert len(baseline) == 1
        assert baseline[0]["ownerid"] == _REDUA
        assert baseline[0]["event_type"] == "HISTORICAL"

    def test_new_event_inherits_the_recovered_owner(
        self, spark_session, snapshot_is_latest_table
    ):
        """End to end: baseline is a snapshot, the incoming event carries no owner."""
        # arrange / act
        conformed = in_memory_cdc_udpate(
            search_for_latest_record(
                spark_session,
                _incoming_sparse_update(spark_session),
                snapshot_is_latest_table,
            )
        )
        written = [row for row in conformed.collect() if row["new_record"]]

        # assert
        assert len(written) == 1
        assert written[0]["ownerid"] == _REDUA  # null in the event -> carried
        assert written[0]["status"] == "Awaiting"  # non-null -> overwrites
