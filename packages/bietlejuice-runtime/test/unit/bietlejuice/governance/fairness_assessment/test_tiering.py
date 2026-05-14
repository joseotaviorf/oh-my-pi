import os
import unittest
from unittest.mock import patch

from bietlejuice.governance.fairness_assessment import (
    DATAHUB_ENTITY_NOT_FOUND,
    DATAHUB_HTTP_ERROR,
    MVP_TIER2_SCOPED_REQUIREMENT_IDS,
    TIER1_ACTIVE_REQUIREMENT_IDS,
    TIER_1_IDS,
    TIER_ACHIEVED_TO_CLASSIFICATION,
    RequirementResult,
    _parse_dataset_fair_signals,
    build_dataset_urn,
    check_a1_2_03_interim_access_policy_via_contract,
    check_f1_03_addressable_fqn,
    check_f4_01_indexed_in_datahub,
    check_i1_02_data_contract_present,
    compute_f4_pass_and_reason_by_fqn,
    compute_has_data_contract_by_fqn,
    compute_tier,
    cumulative_ids_for_tier,
    dataset_id_for_platform,
    evaluate_mvp_checks_from_row,
    institutional_memory_has_assigned_datacontract,
    list_platform_urns_for_fqn,
    resolve_datahub_gms_base_url,
    resolve_datahub_graphql_url,
    tier_achieved_to_classification,
)
from bietlejuice.governance.fairness_assessment.datahub_graphql.client import (
    entity_json_has_data_contract_resource,
)


class TestTierAchievedToClassification(unittest.TestCase):
    def test_map_0_to_4(self):
        self.assertEqual(tier_achieved_to_classification(0), "Not FAIR")
        self.assertEqual(tier_achieved_to_classification(1), "Findable, Accessible")
        self.assertEqual(
            tier_achieved_to_classification(2),
            "Findable, Accessible, Interoperable",
        )
        self.assertEqual(
            tier_achieved_to_classification(3),
            "Findable, Accessible, Interoperable and Reusable",
        )
        self.assertEqual(tier_achieved_to_classification(4), "FAIR Masterpiece")

    def test_labels_frozen(self):
        self.assertEqual(len(TIER_ACHIEVED_TO_CLASSIFICATION), 5)

    def test_unknown_tier_raises(self):
        with self.assertRaises(ValueError):
            tier_achieved_to_classification(99)


class TestComputeTierMvp(unittest.TestCase):
    def test_all_pass_tier_2(self):
        results = {
            rid: RequirementResult(rid, True)
            for rid in MVP_TIER2_SCOPED_REQUIREMENT_IDS
        }
        out = compute_tier(results, mode="mvp")
        self.assertEqual(out.tier_achieved, 2)
        self.assertEqual(out.tier_max_possible, 2)
        self.assertEqual(out.mode, "mvp")

    def test_one_fail_not_fair(self):
        results = {
            rid: RequirementResult(rid, True)
            for rid in MVP_TIER2_SCOPED_REQUIREMENT_IDS
        }
        results["F1-02"] = RequirementResult("F1-02", False, reason="dup")
        out = compute_tier(results, mode="mvp")
        self.assertEqual(out.tier_achieved, 0)

    def test_tier1_only_f2_i1_fail_still_tier1_achievable(self):
        results = {
            rid: RequirementResult(rid, True) for rid in TIER1_ACTIVE_REQUIREMENT_IDS
        }
        results["F2-02"] = RequirementResult("F2-02", False, reason="x")
        results["I1-01"] = RequirementResult("I1-01", True)
        out = compute_tier(results, mode="mvp")
        self.assertEqual(out.tier_achieved, 1)
        self.assertEqual(out.tier_max_possible, 2)

    def test_missing_key_fails_closed(self):
        results = {
            rid: RequirementResult(rid, True)
            for rid in MVP_TIER2_SCOPED_REQUIREMENT_IDS
        }
        del results["F2-01"]
        out = compute_tier(results, mode="mvp")
        self.assertEqual(out.tier_achieved, 0)
        self.assertEqual(out.tier_max_possible, 0)


class TestComputeTierFull(unittest.TestCase):
    def test_partial_implementation_zero_max(self):
        results = {
            rid: RequirementResult(rid, True)
            for rid in MVP_TIER2_SCOPED_REQUIREMENT_IDS
        }
        out = compute_tier(results, mode="full")
        self.assertLess(len(results), len(TIER_1_IDS))
        self.assertEqual(out.tier_max_possible, 0)
        self.assertEqual(out.tier_achieved, 0)

    def test_full_tier1_all_pass(self):
        results = {rid: RequirementResult(rid, True) for rid in TIER_1_IDS}
        out = compute_tier(results, mode="full")
        self.assertEqual(out.tier_max_possible, 1)
        self.assertEqual(out.tier_achieved, 1)

    def test_full_tier1_one_fail(self):
        results = {rid: RequirementResult(rid, True) for rid in TIER_1_IDS}
        results["F1-01"] = RequirementResult("F1-01", False, reason="x")
        out = compute_tier(results, mode="full")
        self.assertEqual(out.tier_achieved, 0)


class TestCumulativeIds(unittest.TestCase):
    def test_tier4_superset(self):
        t3 = cumulative_ids_for_tier(3)
        t4 = cumulative_ids_for_tier(4)
        self.assertTrue(t3 < t4)


class TestUrnBuilding(unittest.TestCase):
    def test_databricks_urn(self):
        did = dataset_id_for_platform("databricks", "core_brokers", "brokers")
        self.assertEqual(did, "core_brokers.brokers")
        urn = build_dataset_urn("databricks", did)
        self.assertEqual(
            urn,
            "urn:li:dataset:(urn:li:dataPlatform:databricks,core_brokers.brokers,PROD)",
        )

    def test_trino_urn_hive_prefix(self):
        did = dataset_id_for_platform("trino", "core_brokers", "brokers")
        self.assertEqual(did, "hive.core_brokers.brokers")
        urn = build_dataset_urn("trino", did)
        self.assertEqual(
            urn,
            "urn:li:dataset:(urn:li:dataPlatform:trino,hive.core_brokers.brokers,PROD)",
        )

    def test_list_platform_urns_both(self):
        pairs = list_platform_urns_for_fqn(
            "core_brokers",
            "brokers",
            server_databricks=True,
            server_trino=True,
        )
        self.assertEqual(len(pairs), 2)
        self.assertTrue(any(p[0] == "databricks" for p in pairs))
        self.assertTrue(any(p[0] == "trino" for p in pairs))


class TestEntityJsonDataContract(unittest.TestCase):
    def test_true_when_datacontract_urn_in_nested_string(self):
        payload = {
            "aspects": {
                "x": {
                    "body": "[Data Contract] urn:prod:datacontract:my.team.dataset@v1",
                }
            }
        }
        self.assertTrue(entity_json_has_data_contract_resource(payload))

    def test_false_placeholder_no_contract_assigned(self):
        payload = {"resources": ["[Data Contract] No data contract assigned"]}
        self.assertFalse(entity_json_has_data_contract_resource(payload))

    def test_false_when_urn_marker_absent(self):
        self.assertFalse(
            entity_json_has_data_contract_resource({"a": "no datacontract urn"})
        )

    def test_false_legacy_suffix_only(self):
        self.assertFalse(entity_json_has_data_contract_resource("[Data Contract]"))


class TestComputeHasDataContractByFqn(unittest.TestCase):
    @staticmethod
    def _row(db, tbl, sd, st):
        class R:
            def __init__(self):
                self._d = {
                    "database_name": db,
                    "table_name": tbl,
                    "contract_server_databricks": sd,
                    "contract_server_trino": st,
                }

            def __getitem__(self, k):
                return self._d[k]

        return R()

    def test_true_when_databricks_urn_has_contract(self):
        rows = [self._row("a", "b", True, True)]
        db_urn = "urn:li:dataset:(urn:li:dataPlatform:databricks,a.b,PROD)"
        m = compute_has_data_contract_by_fqn(rows, {db_urn: True})
        self.assertTrue(m[("a", "b")])

    def test_false_when_server_databricks_disabled(self):
        rows = [self._row("a", "b", False, True)]
        m = compute_has_data_contract_by_fqn(rows, {})
        self.assertFalse(m[("a", "b")])


class TestInstitutionalMemoryDatacontract(unittest.TestCase):
    def test_true_when_label_contains_datacontract_urn(self):
        im = {
            "elements": [
                {"label": "[Data Contract] urn:prod:datacontract:my.team.dataset@v1"}
            ]
        }
        self.assertTrue(institutional_memory_has_assigned_datacontract(im))

    def test_false_placeholder_no_contract_assigned(self):
        im = {"elements": [{"label": "[Data Contract] No data contract assigned"}]}
        self.assertFalse(institutional_memory_has_assigned_datacontract(im))

    def test_false_when_no_elements(self):
        self.assertFalse(
            institutional_memory_has_assigned_datacontract({"elements": []})
        )


class TestParseDatasetFairSignals(unittest.TestCase):
    def test_indexed_and_lineage(self):
        root = {
            "data": {
                "dataset": {
                    "exists": True,
                    "ownership": {"owners": [{"owner": {"urn": "urn:li:corpuser:u"}}]},
                    "upstream": {"total": 2},
                    "downstream": {"total": 0},
                    "institutionalMemory": {"elements": []},
                }
            }
        }
        indexed_ok, has_contract, own_ok, up_n, down_n, had_ds = (
            _parse_dataset_fair_signals(root)
        )
        self.assertTrue(indexed_ok and had_ds)
        self.assertFalse(has_contract)
        self.assertTrue(own_ok)
        self.assertEqual(up_n, 2)
        self.assertEqual(down_n, 0)

    def test_dataset_null(self):
        root = {"data": {"dataset": None}}
        t = _parse_dataset_fair_signals(root)
        self.assertEqual(t, (False, False, False, 0, 0, False))

    def test_contract_from_institutional_memory(self):
        root = {
            "data": {
                "dataset": {
                    "exists": True,
                    "ownership": {"owners": []},
                    "upstream": {"total": 0},
                    "downstream": {"total": 1},
                    "institutionalMemory": {
                        "elements": [
                            {"label": "urn:prod:datacontract:foo@v1", "url": None}
                        ]
                    },
                }
            }
        }
        indexed_ok, has_contract, _, _, _, _ = _parse_dataset_fair_signals(root)
        self.assertTrue(indexed_ok and has_contract)


class TestF4Aggregation(unittest.TestCase):
    def test_f4_passes_when_both_platforms_indexed(self):
        class R:
            def __init__(self, db, tbl, sd, st):
                self._d = {
                    "database_name": db,
                    "table_name": tbl,
                    "contract_server_databricks": sd,
                    "contract_server_trino": st,
                }

            def __getitem__(self, k):
                return self._d[k]

        rows = [R("a", "b", True, True)]
        urn_hit = {
            "urn:li:dataset:(urn:li:dataPlatform:databricks,a.b,PROD)": True,
            "urn:li:dataset:(urn:li:dataPlatform:trino,hive.a.b,PROD)": True,
        }
        m, _ = compute_f4_pass_and_reason_by_fqn(
            rows, urn_hit, {}, datahub_host_configured=True
        )
        self.assertTrue(m[("a", "b")])

    def test_f4_passes_if_only_one_platform_indexed(self):
        class R:
            def __init__(self):
                self._d = {
                    "database_name": "a",
                    "table_name": "b",
                    "contract_server_databricks": True,
                    "contract_server_trino": True,
                }

            def __getitem__(self, k):
                return self._d[k]

        rows = [R()]
        urn_hit = {
            "urn:li:dataset:(urn:li:dataPlatform:databricks,a.b,PROD)": True,
            "urn:li:dataset:(urn:li:dataPlatform:trino,hive.a.b,PROD)": False,
        }
        m, _ = compute_f4_pass_and_reason_by_fqn(
            rows, urn_hit, {}, datahub_host_configured=True
        )
        self.assertTrue(m[("a", "b")])

    def test_f4_fails_if_no_platform_indexed(self):
        class R:
            def __init__(self):
                self._d = {
                    "database_name": "a",
                    "table_name": "b",
                    "contract_server_databricks": True,
                    "contract_server_trino": True,
                }

            def __getitem__(self, k):
                return self._d[k]

        rows = [R()]
        urn_hit = {
            "urn:li:dataset:(urn:li:dataPlatform:databricks,a.b,PROD)": False,
            "urn:li:dataset:(urn:li:dataPlatform:trino,hive.a.b,PROD)": False,
        }
        m, _ = compute_f4_pass_and_reason_by_fqn(
            rows, urn_hit, {}, datahub_host_configured=True
        )
        self.assertFalse(m[("a", "b")])


class TestF4FailureReasons(unittest.TestCase):
    @staticmethod
    def _row(db, tbl, sd, st):
        class R:
            def __init__(self):
                self._d = {
                    "database_name": db,
                    "table_name": tbl,
                    "contract_server_databricks": sd,
                    "contract_server_trino": st,
                }

            def __getitem__(self, k):
                return self._d[k]

        return R()

    def test_host_unconfigured_reason(self):
        rows = [self._row("a", "b", True, True)]
        pass_m, reason_m = compute_f4_pass_and_reason_by_fqn(
            rows, {}, {}, datahub_host_configured=False
        )
        self.assertFalse(pass_m[("a", "b")])
        self.assertEqual(reason_m[("a", "b")], "datahub_host_unconfigured")

    def test_http_error_when_all_platforms_report_http(self):
        rows = [self._row("a", "b", True, True)]
        db_urn = "urn:li:dataset:(urn:li:dataPlatform:databricks,a.b,PROD)"
        tr_urn = "urn:li:dataset:(urn:li:dataPlatform:trino,hive.a.b,PROD)"
        urn_hit = {db_urn: False, tr_urn: False}
        urn_diag = {db_urn: DATAHUB_HTTP_ERROR, tr_urn: DATAHUB_HTTP_ERROR}
        pass_m, reason_m = compute_f4_pass_and_reason_by_fqn(
            rows, urn_hit, urn_diag, datahub_host_configured=True
        )
        self.assertFalse(pass_m[("a", "b")])
        self.assertEqual(reason_m[("a", "b")], DATAHUB_HTTP_ERROR)

    def test_http_error_takes_priority_over_entity_not_found(self):
        rows = [self._row("a", "b", True, True)]
        db_urn = "urn:li:dataset:(urn:li:dataPlatform:databricks,a.b,PROD)"
        tr_urn = "urn:li:dataset:(urn:li:dataPlatform:trino,hive.a.b,PROD)"
        urn_hit = {db_urn: False, tr_urn: False}
        urn_diag = {db_urn: DATAHUB_HTTP_ERROR, tr_urn: DATAHUB_ENTITY_NOT_FOUND}
        pass_m, reason_m = compute_f4_pass_and_reason_by_fqn(
            rows, urn_hit, urn_diag, datahub_host_configured=True
        )
        self.assertFalse(pass_m[("a", "b")])
        self.assertEqual(reason_m[("a", "b")], DATAHUB_HTTP_ERROR)

    def test_entity_not_found_when_all_platforms_missing(self):
        rows = [self._row("a", "b", True, True)]
        db_urn = "urn:li:dataset:(urn:li:dataPlatform:databricks,a.b,PROD)"
        tr_urn = "urn:li:dataset:(urn:li:dataPlatform:trino,hive.a.b,PROD)"
        urn_hit = {db_urn: False, tr_urn: False}
        urn_diag = {db_urn: DATAHUB_ENTITY_NOT_FOUND, tr_urn: DATAHUB_ENTITY_NOT_FOUND}
        pass_m, reason_m = compute_f4_pass_and_reason_by_fqn(
            rows, urn_hit, urn_diag, datahub_host_configured=True
        )
        self.assertFalse(pass_m[("a", "b")])
        self.assertEqual(reason_m[("a", "b")], DATAHUB_ENTITY_NOT_FOUND)


class TestMvpChecks(unittest.TestCase):
    def test_happy_path_row(self):
        row = {
            "database_name": "dw_rent",
            "table_name": "fact_contract",
            "domain": "For Rent",
            "owner": "Someone@quintoandar.com.br",
            "table_description": "Contracts fact",
            "fqn_occurrence_count": 1,
            "is_active_employee": True,
            "spark_table_exists": True,
            "f4_01_pass": True,
            "has_data_contract": True,
            "f2_02_pass": True,
            "i1_01_pass": True,
        }
        res = evaluate_mvp_checks_from_row(row)
        self.assertTrue(all(r.passed for r in res.values()))
        self.assertEqual(set(res.keys()), MVP_TIER2_SCOPED_REQUIREMENT_IDS)

    def test_duplicate_fqn(self):
        row = {
            "database_name": "a",
            "table_name": "b",
            "domain": "For Rent",
            "owner": "a@quintoandar.com.br",
            "table_description": "x",
            "fqn_occurrence_count": 2,
            "is_active_employee": True,
            "spark_table_exists": True,
            "f4_01_pass": True,
            "has_data_contract": True,
            "f2_02_pass": True,
            "i1_01_pass": True,
        }
        res = evaluate_mvp_checks_from_row(row)
        self.assertFalse(res["F1-02"].passed)

    def test_inactive_owner(self):
        row = {
            "database_name": "a",
            "table_name": "b",
            "domain": "For Rent",
            "owner": "a@quintoandar.com.br",
            "table_description": "x",
            "fqn_occurrence_count": 1,
            "is_active_employee": False,
            "spark_table_exists": True,
            "f4_01_pass": True,
            "has_data_contract": True,
            "f2_02_pass": True,
            "i1_01_pass": True,
        }
        res = evaluate_mvp_checks_from_row(row)
        self.assertFalse(res["F2-01"].passed)

    def test_f1_03_fails_when_spark_probe_false(self):
        row = {
            "database_name": "dw_rent",
            "table_name": "fact_contract",
            "domain": "For Rent",
            "owner": "Someone@quintoandar.com.br",
            "table_description": "Contracts fact",
            "fqn_occurrence_count": 1,
            "is_active_employee": True,
            "spark_table_exists": False,
            "f4_01_pass": True,
            "has_data_contract": True,
            "f2_02_pass": True,
            "i1_01_pass": True,
        }
        res = evaluate_mvp_checks_from_row(row)
        self.assertFalse(res["F1-03"].passed)
        self.assertEqual(res["F1-03"].reason, "fqn_not_in_columns_metastore_snapshot")

    def test_f1_03_missing_maps_to_fqn_not_in_snapshot(self):
        row = {
            "database_name": "dw_rent",
            "table_name": "fact_contract",
            "domain": "For Rent",
            "owner": "Someone@quintoandar.com.br",
            "table_description": "Contracts fact",
            "fqn_occurrence_count": 1,
            "is_active_employee": True,
            "spark_table_exists": False,
            "spark_catalog_probe_status": "missing_in_snapshot",
            "f4_01_pass": True,
            "has_data_contract": True,
            "f2_02_pass": True,
            "i1_01_pass": True,
        }
        res = evaluate_mvp_checks_from_row(row)
        self.assertFalse(res["F1-03"].passed)
        self.assertEqual(res["F1-03"].reason, "fqn_not_in_columns_metastore_snapshot")

    def test_f1_03_passes_when_spark_probe_true(self):
        row = {
            "database_name": "dw_rent",
            "table_name": "fact_contract",
            "domain": "For Rent",
            "owner": "Someone@quintoandar.com.br",
            "table_description": "Contracts fact",
            "fqn_occurrence_count": 1,
            "is_active_employee": True,
            "spark_table_exists": True,
            "f4_01_pass": True,
            "has_data_contract": True,
            "f2_02_pass": True,
            "i1_01_pass": True,
        }
        res = evaluate_mvp_checks_from_row(row)
        self.assertTrue(res["F1-03"].passed)

    def test_f1_03_fails_when_spark_probe_absent_from_row(self):
        row = {
            "database_name": "dw_rent",
            "table_name": "fact_contract",
            "domain": "For Rent",
            "owner": "Someone@quintoandar.com.br",
            "table_description": "Contracts fact",
            "fqn_occurrence_count": 1,
            "is_active_employee": True,
            "f4_01_pass": True,
            "has_data_contract": True,
            "f2_02_pass": True,
            "i1_01_pass": True,
        }
        res = evaluate_mvp_checks_from_row(row)
        self.assertFalse(res["F1-03"].passed)
        self.assertEqual(res["F1-03"].reason, "columns_metastore_snapshot_unavailable")

    def test_f1_03_fails_not_assessed_when_spark_probe_value_is_none(self):
        row = {
            "database_name": "dw_rent",
            "table_name": "fact_contract",
            "domain": "For Rent",
            "owner": "Someone@quintoandar.com.br",
            "table_description": "Contracts fact",
            "fqn_occurrence_count": 1,
            "is_active_employee": True,
            "spark_table_exists": None,
            "f4_01_pass": True,
            "has_data_contract": True,
            "f2_02_pass": True,
            "i1_01_pass": True,
        }
        res = evaluate_mvp_checks_from_row(row)
        self.assertFalse(res["F1-03"].passed)
        self.assertEqual(res["F1-03"].reason, "columns_metastore_snapshot_unavailable")

    def test_i1_fails_without_contract(self):
        row = {
            "database_name": "dw_rent",
            "table_name": "fact_contract",
            "domain": "For Rent",
            "owner": "Someone@quintoandar.com.br",
            "table_description": "Contracts fact",
            "fqn_occurrence_count": 1,
            "is_active_employee": True,
            "spark_table_exists": True,
            "f4_01_pass": True,
            "has_data_contract": False,
            "f2_02_pass": True,
            "i1_01_pass": True,
        }
        res = evaluate_mvp_checks_from_row(row)
        self.assertFalse(res["I1-02"].passed)
        self.assertEqual(
            res["I1-02"].reason, "no_assigned_data_contract_urn_in_databricks_entity"
        )
        self.assertFalse(res["A1.2-03"].passed)
        self.assertEqual(
            res["A1.2-03"].reason, "a1_2_03_interim_requires_assigned_data_contract"
        )

    def test_f4_explicit_failure_reason_from_row(self):
        row = {
            "database_name": "dw_rent",
            "table_name": "fact_contract",
            "domain": "For Rent",
            "owner": "Someone@quintoandar.com.br",
            "table_description": "Contracts fact",
            "fqn_occurrence_count": 1,
            "is_active_employee": True,
            "spark_table_exists": True,
            "f4_01_pass": False,
            "f4_01_failure_reason": "datahub_host_unconfigured",
            "has_data_contract": False,
            "f2_02_pass": True,
            "i1_01_pass": True,
        }
        res = evaluate_mvp_checks_from_row(row)
        self.assertFalse(res["F4-01"].passed)
        self.assertEqual(res["F4-01"].reason, "datahub_host_unconfigured")


class TestF103Direct(unittest.TestCase):
    def test_fails_without_catalog_probe(self):
        r = check_f1_03_addressable_fqn("s", "t", spark_catalog_hit=None)
        self.assertFalse(r.passed)
        self.assertEqual(r.reason, "columns_metastore_snapshot_unavailable")

    def test_passes_with_catalog_hit(self):
        r = check_f1_03_addressable_fqn("s", "t", spark_catalog_hit=True)
        self.assertTrue(r.passed)

    def test_catalog_miss_explicit(self):
        r = check_f1_03_addressable_fqn("s", "t", spark_catalog_hit=False)
        self.assertFalse(r.passed)
        self.assertEqual(r.reason, "fqn_not_in_columns_metastore_snapshot")

    def test_snapshot_unavailable_probe(self):
        r = check_f1_03_addressable_fqn(
            "s",
            "t",
            spark_catalog_hit=False,
            spark_catalog_probe_status="snapshot_unavailable",
        )
        self.assertFalse(r.passed)
        self.assertEqual(r.reason, "columns_metastore_snapshot_unavailable")


class _FakeConfigService:
    """Minimal stand-in for ``ConfigurationService`` (only ``configs`` dict)."""

    __slots__ = ("configs",)

    def __init__(self, configs: dict):
        self.configs = dict(configs)


class TestResolveDatahubGmsBaseUrl(unittest.TestCase):
    @patch.dict(
        os.environ, {"DATAHUB_GMS_HOST": "https://from-airflow.example"}, clear=False
    )
    def test_env_wins_over_yaml(self):
        cfg = _FakeConfigService({"datahub_gms_host": "https://from-yaml.example"})
        self.assertEqual(
            resolve_datahub_gms_base_url(cfg), "https://from-airflow.example"
        )

    def test_yaml_when_env_empty(self):
        cfg = _FakeConfigService({"datahub_gms_host": "https://from-yaml.example"})
        with patch.dict(os.environ, {"DATAHUB_GMS_HOST": ""}):
            self.assertEqual(
                resolve_datahub_gms_base_url(cfg), "https://from-yaml.example"
            )

    def test_empty_when_missing_everywhere(self):
        cfg = _FakeConfigService({})
        with patch.dict(os.environ, {"DATAHUB_GMS_HOST": ""}):
            self.assertEqual(resolve_datahub_gms_base_url(cfg), "")


class TestResolveDatahubGraphqlUrl(unittest.TestCase):
    @patch.dict(
        os.environ,
        {"DATAHUB_GRAPHQL_URL": "https://gql.example/api/graphql"},
        clear=False,
    )
    def test_graphql_env_wins(self):
        cfg = _FakeConfigService(
            {
                "datahub_graphql_url": "https://ignored.example/api/graphql",
                "datahub_host": "https://ignored.example",
            }
        )
        self.assertEqual(
            resolve_datahub_graphql_url(cfg), "https://gql.example/api/graphql"
        )

    def test_explicit_yaml(self):
        cfg = _FakeConfigService(
            {
                "datahub_graphql_url": "https://explicit.example/api/graphql",
                "datahub_host": "https://h.example",
            }
        )
        with patch.dict(os.environ, {"DATAHUB_GRAPHQL_URL": ""}):
            self.assertEqual(
                resolve_datahub_graphql_url(cfg), "https://explicit.example/api/graphql"
            )

    def test_derived_from_datahub_host(self):
        cfg = _FakeConfigService({"datahub_host": "https://datahub.apps.example"})
        with patch.dict(os.environ, {"DATAHUB_GRAPHQL_URL": ""}):
            self.assertEqual(
                resolve_datahub_graphql_url(cfg),
                "https://datahub.apps.example/api/graphql",
            )

    def test_empty_when_missing(self):
        cfg = _FakeConfigService({})
        with patch.dict(os.environ, {"DATAHUB_GRAPHQL_URL": ""}):
            self.assertEqual(resolve_datahub_graphql_url(cfg), "")


class TestF4I1Direct(unittest.TestCase):
    def test_f4_direct(self):
        self.assertTrue(check_f4_01_indexed_in_datahub(True).passed)
        fail = check_f4_01_indexed_in_datahub(False)
        self.assertFalse(fail.passed)
        self.assertEqual(fail.reason, DATAHUB_ENTITY_NOT_FOUND)
        r = check_f4_01_indexed_in_datahub(False, failure_reason=DATAHUB_HTTP_ERROR)
        self.assertEqual(r.reason, DATAHUB_HTTP_ERROR)

    def test_i1_direct(self):
        self.assertTrue(check_i1_02_data_contract_present(True).passed)
        self.assertFalse(check_i1_02_data_contract_present(False).passed)

    def test_a1_2_03_direct_mirrors_contract_boolean(self):
        self.assertTrue(check_a1_2_03_interim_access_policy_via_contract(True).passed)
        self.assertFalse(check_a1_2_03_interim_access_policy_via_contract(False).passed)


if __name__ == "__main__":
    unittest.main()
