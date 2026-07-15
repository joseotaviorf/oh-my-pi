import unittest
from unittest.mock import patch

from bietlejuice.governance.fairness_assessment import (
    DATAHUB_SP_DATA_CONTRACT_URN,
    DATAHUB_SP_FAIRNESS_CLASSIFICATION_URN,
    DATAHUB_SP_HOW_TO_REQUEST_ACCESS_URN,
    build_dataset_fqn_search_query,
    build_upsert_structured_property_mutation,
    dataset_name_from_urn,
    find_matching_dataset_urns,
    fqn_matches,
    parse_search_result_urns,
    push_classifications,
    structured_property_rows_from_fetch,
)
from bietlejuice.governance.fairness_assessment.datahub_graphql.upsert_structured_property import (  # noqa: E501
    DATASET_FQN_SEARCH_COUNT,
)

_POST_PATH = (
    "bietlejuice.governance.fairness_assessment.datahub_graphql."
    "upsert_structured_property.datahub_graphql_post"
)

_DB = "datalake_x_clean"
_TABLE = "cypress_reports"
_TRINO_URN = f"urn:li:dataset:(urn:li:dataPlatform:trino,hive.{_DB}.{_TABLE},PROD)"
_DATABRICKS_URN = f"urn:li:dataset:(urn:li:dataPlatform:databricks,{_DB}.{_TABLE},PROD)"
_OTHER_URN = f"urn:li:dataset:(urn:li:dataPlatform:trino,hive.{_DB}.other_table,PROD)"


def _search_root(*urns):
    return {
        "data": {
            "searchAcrossEntities": {
                "total": len(urns),
                "searchResults": [{"entity": {"urn": u}} for u in urns],
            }
        }
    }


def _fetch_sp_root(*props):
    """``props`` is an iterable of ``(sp_urn, string_value)`` pairs."""
    return {
        "data": {
            "dataset": {
                "structuredProperties": {
                    "properties": [
                        {
                            "structuredProperty": {"urn": sp_urn},
                            "values": [{"stringValue": value}],
                        }
                        for sp_urn, value in props
                    ]
                }
            }
        }
    }


def _upsert_ok_root():
    return {
        "data": {
            "upsertStructuredProperties": {
                "properties": [{"structuredProperty": {"urn": "x"}}]
            }
        }
    }


def _routing_post(search_root, upsert_root=None, fetch_root=None):
    """Fake ``datahub_graphql_post`` that routes by query text (search / fetch / mutation)."""

    upsert_root = upsert_root if upsert_root is not None else _upsert_ok_root()
    fetch_root = fetch_root if fetch_root is not None else _fetch_sp_root()

    def _post(url, token, query, variables, timeout_sec=60.0):
        if "searchAcrossEntities" in query:
            return search_root, "OK"
        if "FetchDatasetStructuredProperties" in query or (
            "dataset(urn:" in query and "structuredProperties" in query
        ):
            return fetch_root, "OK"
        if "upsertStructuredProperties" in query:
            return upsert_root, "OK"
        raise AssertionError(f"unexpected query: {query}")

    return _post


class TestDatasetNameFromUrn(unittest.TestCase):
    def test_trino(self):
        self.assertEqual(dataset_name_from_urn(_TRINO_URN), f"hive.{_DB}.{_TABLE}")

    def test_databricks(self):
        self.assertEqual(dataset_name_from_urn(_DATABRICKS_URN), f"{_DB}.{_TABLE}")

    def test_malformed_returns_none(self):
        self.assertIsNone(dataset_name_from_urn("not-a-urn"))
        self.assertIsNone(dataset_name_from_urn(""))


class TestFqnMatches(unittest.TestCase):
    def test_trino_and_databricks_match(self):
        self.assertTrue(fqn_matches(f"hive.{_DB}.{_TABLE}", _DB, _TABLE))
        self.assertTrue(fqn_matches(f"{_DB}.{_TABLE}", _DB, _TABLE))

    def test_different_table_does_not_match(self):
        self.assertFalse(fqn_matches(f"hive.{_DB}.other_table", _DB, _TABLE))

    def test_different_db_does_not_match(self):
        self.assertFalse(fqn_matches(f"hive.other_db.{_TABLE}", _DB, _TABLE))

    def test_too_few_segments_or_none(self):
        self.assertFalse(fqn_matches(_TABLE, _DB, _TABLE))
        self.assertFalse(fqn_matches(None, _DB, _TABLE))


class TestParseSearchResultUrns(unittest.TestCase):
    def test_extracts_urns(self):
        root = _search_root(_TRINO_URN, _DATABRICKS_URN)
        self.assertEqual(parse_search_result_urns(root), [_TRINO_URN, _DATABRICKS_URN])

    def test_empty_and_malformed(self):
        self.assertEqual(parse_search_result_urns({}), [])
        self.assertEqual(parse_search_result_urns({"data": {}}), [])
        self.assertEqual(
            parse_search_result_urns(
                {
                    "data": {
                        "searchAcrossEntities": {"searchResults": [{}, {"entity": {}}]}
                    }
                }
            ),
            [],
        )


class TestStructuredPropertyRowsFromFetch(unittest.TestCase):
    def test_round_trips_string_and_number_and_skips_target(self):
        root = {
            "data": {
                "dataset": {
                    "structuredProperties": {
                        "properties": [
                            {
                                "structuredProperty": {
                                    "urn": DATAHUB_SP_DATA_CONTRACT_URN
                                },
                                "values": [{"stringValue": "yes"}],
                            },
                            {
                                "structuredProperty": {
                                    "urn": DATAHUB_SP_FAIRNESS_CLASSIFICATION_URN
                                },
                                "values": [{"stringValue": "Not FAIR"}],
                            },
                            {
                                "structuredProperty": {
                                    "urn": "urn:li:structuredProperty:n"
                                },
                                "values": [{"numberValue": 3}],
                            },
                        ]
                    }
                }
            }
        }
        rows = structured_property_rows_from_fetch(
            root, skip_sp_urns=frozenset({DATAHUB_SP_FAIRNESS_CLASSIFICATION_URN})
        )
        urns = {r["structuredPropertyUrn"] for r in rows}
        self.assertEqual(
            urns, {DATAHUB_SP_DATA_CONTRACT_URN, "urn:li:structuredProperty:n"}
        )
        by_urn = {r["structuredPropertyUrn"]: r["values"] for r in rows}
        self.assertEqual(by_urn[DATAHUB_SP_DATA_CONTRACT_URN], [{"stringValue": "yes"}])
        self.assertEqual(by_urn["urn:li:structuredProperty:n"], [{"numberValue": 3}])


class TestBuildDatasetFqnSearchQuery(unittest.TestCase):
    def test_default_count_is_search_page_size(self):
        # Caps how many fuzzy hits we pull before exact FQN filtering; see DATASET_FQN_SEARCH_COUNT.
        _query, variables = build_dataset_fqn_search_query(f"{_DB}.{_TABLE}")
        self.assertEqual(variables["count"], DATASET_FQN_SEARCH_COUNT)
        self.assertEqual(DATASET_FQN_SEARCH_COUNT, 50)

    def test_custom_count_is_honoured(self):
        _query, variables = build_dataset_fqn_search_query(f"{_DB}.{_TABLE}", count=10)
        self.assertEqual(variables["count"], 10)


class TestBuildUpsertMutation(unittest.TestCase):
    def test_shape_merges_existing_siblings(self):
        existing = [
            {
                "structuredPropertyUrn": DATAHUB_SP_DATA_CONTRACT_URN,
                "values": [{"stringValue": "yes"}],
            }
        ]
        query, variables = build_upsert_structured_property_mutation(
            _TRINO_URN,
            DATAHUB_SP_FAIRNESS_CLASSIFICATION_URN,
            "FAIR Tier 1",
            existing_property_params=existing,
        )
        self.assertIn("upsertStructuredProperties", query)
        params = variables["input"]["structuredPropertyInputParams"]
        self.assertEqual(variables["input"]["assetUrn"], _TRINO_URN)
        self.assertEqual(len(params), 2)
        self.assertEqual(
            params[0]["structuredPropertyUrn"], DATAHUB_SP_DATA_CONTRACT_URN
        )
        self.assertEqual(
            params[1],
            {
                "structuredPropertyUrn": DATAHUB_SP_FAIRNESS_CLASSIFICATION_URN,
                "values": [{"stringValue": "FAIR Tier 1"}],
            },
        )


class TestFindMatchingDatasetUrns(unittest.TestCase):
    def test_keeps_only_exact_fqn_matches(self):
        with patch(
            _POST_PATH,
            return_value=(_search_root(_TRINO_URN, _DATABRICKS_URN, _OTHER_URN), "OK"),
        ):
            urns = find_matching_dataset_urns("http://gql", "tok", _DB, _TABLE)
        self.assertEqual(set(urns), {_TRINO_URN, _DATABRICKS_URN})

    def test_none_on_post_failure(self):
        with patch(_POST_PATH, return_value=(None, "HTTP_ERROR")):
            self.assertIsNone(
                find_matching_dataset_urns("http://gql", "tok", _DB, _TABLE)
            )

    def test_empty_when_no_match(self):
        with patch(_POST_PATH, return_value=(_search_root(_OTHER_URN), "OK")):
            self.assertEqual(
                find_matching_dataset_urns("http://gql", "tok", _DB, _TABLE), []
            )


class TestPushClassifications(unittest.TestCase):
    def test_happy_path_upserts_all_matched(self):
        rows = [(_DB, _TABLE, "FAIR Tier 1")]
        with patch(
            _POST_PATH,
            side_effect=_routing_post(_search_root(_TRINO_URN, _DATABRICKS_URN)),
        ):
            summary = push_classifications("http://gql", "tok", rows)
        self.assertEqual(summary["total_fqns"], 1)
        self.assertEqual(summary["fqns_with_upsert"], 1)
        self.assertEqual(summary["upserted_entities"], 2)

    def test_merge_preserves_sibling_structured_properties(self):
        # Regression for Bugbot: upsertStructuredProperties replaces the whole aspect.
        rows = [(_DB, _TABLE, "FAIR Tier 1")]
        captured_params = []
        fetch = _fetch_sp_root(
            (DATAHUB_SP_DATA_CONTRACT_URN, "contract-v1"),
            (DATAHUB_SP_HOW_TO_REQUEST_ACCESS_URN, "ask-team"),
            (DATAHUB_SP_FAIRNESS_CLASSIFICATION_URN, "Not FAIR"),
        )

        def _post(url, token, query, variables, timeout_sec=60.0):
            if "searchAcrossEntities" in query:
                return _search_root(_TRINO_URN), "OK"
            if (
                "structuredProperties" in query
                and "upsertStructuredProperties" not in query
            ):
                return fetch, "OK"
            captured_params.append(variables["input"]["structuredPropertyInputParams"])
            return _upsert_ok_root(), "OK"

        with patch(_POST_PATH, side_effect=_post):
            summary = push_classifications("http://gql", "tok", rows)

        self.assertEqual(summary["upserted_entities"], 1)
        self.assertEqual(len(captured_params), 1)
        urns = {p["structuredPropertyUrn"] for p in captured_params[0]}
        self.assertEqual(
            urns,
            {
                DATAHUB_SP_DATA_CONTRACT_URN,
                DATAHUB_SP_HOW_TO_REQUEST_ACCESS_URN,
                DATAHUB_SP_FAIRNESS_CLASSIFICATION_URN,
            },
        )
        fairness = next(
            p
            for p in captured_params[0]
            if p["structuredPropertyUrn"] == DATAHUB_SP_FAIRNESS_CLASSIFICATION_URN
        )
        self.assertEqual(fairness["values"], [{"stringValue": "FAIR Tier 1"}])

    def test_legacy_label_is_normalized_and_pushed(self):
        rows = [(_DB, _TABLE, "Findable, Accessible")]
        captured = {}

        def _post(url, token, query, variables, timeout_sec=60.0):
            if "searchAcrossEntities" in query:
                return _search_root(_TRINO_URN), "OK"
            if (
                "structuredProperties" in query
                and "upsertStructuredProperties" not in query
            ):
                return _fetch_sp_root(), "OK"
            params = variables["input"]["structuredPropertyInputParams"]
            fairness = next(
                p
                for p in params
                if p["structuredPropertyUrn"] == DATAHUB_SP_FAIRNESS_CLASSIFICATION_URN
            )
            captured["value"] = fairness["values"][0]["stringValue"]
            return _upsert_ok_root(), "OK"

        with patch(_POST_PATH, side_effect=_post):
            summary = push_classifications("http://gql", "tok", rows)
        self.assertEqual(captured["value"], "FAIR Tier 1")
        self.assertEqual(summary["upserted_entities"], 1)

    def test_unknown_classification_skipped(self):
        rows = [(_DB, _TABLE, "garbage")]
        with patch(_POST_PATH) as post:
            summary = push_classifications("http://gql", "tok", rows)
        post.assert_not_called()
        self.assertEqual(summary["skipped_unknown_classification"], 1)
        self.assertEqual(summary["upserted_entities"], 0)

    def test_no_matching_dataset(self):
        rows = [(_DB, _TABLE, "FAIR Tier 2")]
        with patch(_POST_PATH, side_effect=_routing_post(_search_root(_OTHER_URN))):
            summary = push_classifications("http://gql", "tok", rows)
        self.assertEqual(summary["skipped_no_matching_dataset"], 1)
        self.assertEqual(summary["upserted_entities"], 0)

    def test_datahub_unreachable_on_search(self):
        rows = [(_DB, _TABLE, "FAIR Tier 3")]
        with patch(_POST_PATH, return_value=(None, "HTTP_ERROR")):
            summary = push_classifications("http://gql", "tok", rows)
        self.assertEqual(summary["skipped_datahub_unreachable"], 1)

    def test_matched_but_upsert_failed_is_counted(self):
        # Search finds URNs, but every upsert returns a null payload (e.g. auth / SP rejection).
        rows = [(_DB, _TABLE, "FAIR Tier 1")]
        with patch(
            _POST_PATH,
            side_effect=_routing_post(
                _search_root(_TRINO_URN, _DATABRICKS_URN),
                upsert_root={"data": {"upsertStructuredProperties": None}},
            ),
        ):
            summary = push_classifications("http://gql", "tok", rows)
        self.assertEqual(summary["matched_but_upsert_failed"], 1)
        self.assertEqual(summary["fqns_with_upsert"], 0)
        self.assertEqual(summary["upserted_entities"], 0)

    def test_matched_but_upsert_http_failure_is_counted(self):
        rows = [(_DB, _TABLE, "FAIR Tier 2")]

        def _post(url, token, query, variables, timeout_sec=60.0):
            if "searchAcrossEntities" in query:
                return _search_root(_TRINO_URN), "OK"
            if (
                "structuredProperties" in query
                and "upsertStructuredProperties" not in query
            ):
                return _fetch_sp_root(), "OK"
            return None, "HTTP_ERROR"

        with patch(_POST_PATH, side_effect=_post):
            summary = push_classifications("http://gql", "tok", rows)
        self.assertEqual(summary["matched_but_upsert_failed"], 1)
        self.assertEqual(summary["upserted_entities"], 0)

    def test_empty_url_skips_entirely(self):
        rows = [(_DB, _TABLE, "FAIR Tier 1")]
        with patch(_POST_PATH) as post:
            summary = push_classifications("", "tok", rows)
        post.assert_not_called()
        self.assertEqual(summary["skipped_reason"], "datahub_host_unconfigured")

    def test_blank_and_null_fqn_rows_ignored(self):
        rows = [(None, _TABLE, "FAIR Tier 1"), (_DB, "  ", "FAIR Tier 1")]
        with patch(_POST_PATH) as post:
            summary = push_classifications("http://gql", "tok", rows)
        post.assert_not_called()
        self.assertEqual(summary["total_fqns"], 0)


if __name__ == "__main__":
    unittest.main()
