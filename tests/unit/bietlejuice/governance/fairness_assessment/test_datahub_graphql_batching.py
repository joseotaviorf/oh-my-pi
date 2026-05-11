"""Batched ``resolve_datahub_urn_flags``: aliased GraphQL POSTs + ThreadPoolExecutor merge."""

from __future__ import annotations

import unittest
from unittest import mock

from bietlejuice.governance.fairness_assessment.constants import (
    DATAHUB_ENTITY_NOT_FOUND,
    DATAHUB_HTTP_ERROR,
    DATAHUB_URN_DIAG_OK,
)
from bietlejuice.governance.fairness_assessment.datahub_graphql import (
    compute_fqn_datahub_signals,
)
from bietlejuice.governance.fairness_assessment.datahub_graphql.client import (
    build_dataset_fair_signals_batch_query,
    parse_batch_fair_signals,
)


_GRAPHQL_URL = "https://datahub.example/api/graphql"


def _databricks_urn(db: str, tbl: str) -> str:
    return f"urn:li:dataset:(urn:li:dataPlatform:databricks,{db}.{tbl},PROD)"


def _row(db: str, tbl: str, *, srv_db: bool = True, srv_trino: bool = False) -> dict:
    return {
        "database_name": db,
        "table_name": tbl,
        "contract_server_databricks": srv_db,
        "contract_server_trino": srv_trino,
    }


def _ok_dataset_node(*, ownership: bool = True, up: int = 0, down: int = 0) -> dict:
    return {
        "exists": True,
        "ownership": {"owners": [{"owner": {"urn": "x"}}] if ownership else []},
        "upstream": {"total": up},
        "downstream": {"total": down},
        "institutionalMemory": {"elements": []},
    }


def _ok_root(urns: list[str]) -> dict:
    return {
        "data": {f"d{i}": _ok_dataset_node() for i, _ in enumerate(urns)},
    }


class TestBuildBatchQuery(unittest.TestCase):
    def test_query_uses_indexed_aliases_and_variables(self):
        urns = ["urn:a", "urn:b", "urn:c"]
        query, variables = build_dataset_fair_signals_batch_query(urns)

        for i in range(3):
            self.assertIn(f"d{i}: dataset(urn: $u{i})", query)
            self.assertIn(f"$u{i}: String!", query)
        self.assertEqual(variables, {"u0": "urn:a", "u1": "urn:b", "u2": "urn:c"})
        self.assertIn("exists", query)
        self.assertIn("institutionalMemory", query)
        self.assertIn("upstream: lineage", query)
        self.assertIn("downstream: lineage", query)

    def test_empty_urns_returns_noop_query(self):
        query, variables = build_dataset_fair_signals_batch_query([])

        self.assertEqual(variables, {})
        self.assertIn("__typename", query)


class TestParseBatchFairSignals(unittest.TestCase):
    def test_aliases_map_back_to_urns_in_order(self):
        urns = ["urn:ok", "urn:notfound", "urn:notindexed"]
        root = {
            "data": {
                "d0": _ok_dataset_node(ownership=True, up=2, down=3),
                "d1": None,
                "d2": {
                    "exists": False,
                    "ownership": {"owners": []},
                    "upstream": {"total": 0},
                    "downstream": {"total": 0},
                    "institutionalMemory": {"elements": []},
                },
            }
        }

        out = parse_batch_fair_signals(root, urns)

        self.assertEqual(out["urn:ok"], (True, False, True, 2, 3, True))
        self.assertEqual(out["urn:notfound"], (False, False, False, 0, 0, False))
        # had_dataset=True but indexed_ok=False (caller treats as ENTITY_NOT_FOUND).
        self.assertEqual(out["urn:notindexed"], (False, False, False, 0, 0, True))

    def test_missing_data_block_returns_falses_for_every_urn(self):
        out = parse_batch_fair_signals({}, ["urn:a", "urn:b"])

        self.assertEqual(out["urn:a"], (False, False, False, 0, 0, False))
        self.assertEqual(out["urn:b"], (False, False, False, 0, 0, False))


class TestResolveDatahubUrnFlagsBatching(unittest.TestCase):
    def test_chunks_60_urns_into_three_calls_of_25_25_10(self):
        rows = [_row(f"db{i}", f"t{i}") for i in range(60)]

        captured_batches: list[list[str]] = []

        def fake_post(url, token, query, variables, timeout_sec=60.0):
            ordered = [variables[f"u{i}"] for i in range(len(variables))]
            captured_batches.append(ordered)
            return _ok_root(ordered), DATAHUB_URN_DIAG_OK

        with mock.patch.object(
            compute_fqn_datahub_signals, "datahub_graphql_post", side_effect=fake_post
        ):
            (
                urn_hit,
                urn_contract,
                urn_diagnostic,
                urn_ownership,
                urn_upstream_total,
                urn_downstream_total,
            ) = compute_fqn_datahub_signals.resolve_datahub_urn_flags(
                _GRAPHQL_URL, "tok", rows
            )

        self.assertEqual(len(captured_batches), 3)
        self.assertEqual(sorted(len(b) for b in captured_batches), [10, 25, 25])
        self.assertEqual(len(urn_hit), 60)
        self.assertTrue(all(urn_hit.values()))
        self.assertTrue(all(d == DATAHUB_URN_DIAG_OK for d in urn_diagnostic.values()))
        self.assertTrue(all(urn_ownership.values()))
        # Sanity: dicts are URN-keyed, batch order does not matter.
        first_urn = _databricks_urn("db0", "t0")
        self.assertIn(first_urn, urn_hit)
        self.assertEqual(
            urn_contract[first_urn], False
        )  # ownership signal, no contract.
        self.assertEqual(urn_upstream_total[first_urn], 0)
        self.assertEqual(urn_downstream_total[first_urn], 0)

    def test_batch_failure_marks_every_urn_in_that_batch_only(self):
        rows = [_row(f"db{i}", f"t{i}") for i in range(60)]
        target_first_urn = _databricks_urn("db0", "t0")

        def fake_post(url, token, query, variables, timeout_sec=60.0):
            ordered = [variables[f"u{i}"] for i in range(len(variables))]
            if ordered[0] == target_first_urn:
                return None, DATAHUB_HTTP_ERROR
            return _ok_root(ordered), DATAHUB_URN_DIAG_OK

        with mock.patch.object(
            compute_fqn_datahub_signals, "datahub_graphql_post", side_effect=fake_post
        ):
            (
                urn_hit,
                _urn_contract,
                urn_diagnostic,
                _urn_ownership,
                _urn_up,
                _urn_down,
            ) = compute_fqn_datahub_signals.resolve_datahub_urn_flags(
                _GRAPHQL_URL, "tok", rows
            )

        # First 25 URNs (db0..db24) belong to the failed batch.
        failed_urns = [_databricks_urn(f"db{i}", f"t{i}") for i in range(25)]
        for u in failed_urns:
            self.assertFalse(urn_hit[u])
            self.assertEqual(urn_diagnostic[u], DATAHUB_HTTP_ERROR)

        # Remaining 35 URNs are unaffected.
        ok_urns = [_databricks_urn(f"db{i}", f"t{i}") for i in range(25, 60)]
        for u in ok_urns:
            self.assertTrue(urn_hit[u])
            self.assertEqual(urn_diagnostic[u], DATAHUB_URN_DIAG_OK)

    def test_env_override_changes_batch_size(self):
        rows = [_row(f"db{i}", f"t{i}") for i in range(25)]
        captured_sizes: list[int] = []

        def fake_post(url, token, query, variables, timeout_sec=60.0):
            captured_sizes.append(len(variables))
            ordered = [variables[f"u{i}"] for i in range(len(variables))]
            return _ok_root(ordered), DATAHUB_URN_DIAG_OK

        with mock.patch.dict(
            "os.environ", {"DATAHUB_GRAPHQL_BATCH_SIZE": "10"}, clear=False
        ), mock.patch.object(
            compute_fqn_datahub_signals, "datahub_graphql_post", side_effect=fake_post
        ):
            compute_fqn_datahub_signals.resolve_datahub_urn_flags(
                _GRAPHQL_URL, "tok", rows
            )

        self.assertEqual(sorted(captured_sizes), [5, 10, 10])

    def test_unknown_urn_in_batch_marks_only_that_urn_as_not_found(self):
        rows = [_row(f"db{i}", f"t{i}") for i in range(3)]
        unknown_urn = _databricks_urn("db1", "t1")

        def fake_post(url, token, query, variables, timeout_sec=60.0):
            ordered = [variables[f"u{i}"] for i in range(len(variables))]
            data = {}
            for i, urn in enumerate(ordered):
                data[f"d{i}"] = None if urn == unknown_urn else _ok_dataset_node()
            return {"data": data}, DATAHUB_URN_DIAG_OK

        with mock.patch.object(
            compute_fqn_datahub_signals, "datahub_graphql_post", side_effect=fake_post
        ):
            urn_hit, _, urn_diagnostic, *_ = (
                compute_fqn_datahub_signals.resolve_datahub_urn_flags(
                    _GRAPHQL_URL, "tok", rows
                )
            )

        self.assertFalse(urn_hit[unknown_urn])
        self.assertEqual(urn_diagnostic[unknown_urn], DATAHUB_ENTITY_NOT_FOUND)
        for db, tbl in (("db0", "t0"), ("db2", "t2")):
            urn = _databricks_urn(db, tbl)
            self.assertTrue(urn_hit[urn])
            self.assertEqual(urn_diagnostic[urn], DATAHUB_URN_DIAG_OK)

    def test_empty_input_returns_empty_dicts_without_calling_post(self):
        with mock.patch.object(
            compute_fqn_datahub_signals, "datahub_graphql_post"
        ) as post:
            out = compute_fqn_datahub_signals.resolve_datahub_urn_flags(
                _GRAPHQL_URL, None, []
            )

        post.assert_not_called()
        self.assertEqual([len(d) for d in out], [0, 0, 0, 0, 0, 0])


if __name__ == "__main__":
    unittest.main()
