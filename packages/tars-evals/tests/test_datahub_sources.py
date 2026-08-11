from tars_evals.datahub_mock import entities, sources
from tars_evals.datahub_mock.entities import (
    dataset_urn,
    parse_dataset_urn,
    query_urn,
)
from tars_evals.repo_bootstrap import load_document_parser, repo_root


def test_repo_root_has_llm_context():
    assert (sources.repo_root() / "docs/llm_context").is_dir()


def test_sources_share_repo_bootstrap():
    assert sources.repo_root is repo_root
    assert sources._document_parser is load_document_parser
    assert sources._document_parser() is load_document_parser()
    assert sources._document_parser().__name__ == "tars_evals_document_parser"


def test_loads_chatbot_data_product_with_golden_query():
    dps = sources.load_data_products()
    assert "chatbot-sessions" in dps
    dp = dps["chatbot-sessions"]
    assert dp.name
    assert dp.golden_queries, "expected at least one golden query"
    assert any("select" in gq.sql.lower() for gq in dp.golden_queries)


def test_column_index_resolves_a_known_offboarding_table():
    idx = sources.column_index()
    key = ("dw_offboarding", "obt_offboarding")
    assert key in idx, f"missing {key}; sample keys: {list(idx)[:5]}"
    fields = idx[key]
    assert fields and all("fieldPath" in f for f in fields)


def test_dataset_urn_roundtrip():
    u = dataset_urn("dw_offboarding", "obt_offboarding")
    assert u == (
        "urn:li:dataset:(urn:li:dataPlatform:trino,"
        "hive.dw_offboarding.obt_offboarding,PROD)"
    )
    assert parse_dataset_urn(u) == ("dw_offboarding", "obt_offboarding")


def test_query_urn_deterministic():
    a = query_urn("chatbot-sessions", 0)
    assert a.startswith("urn:li:query:")
    assert a == query_urn("chatbot-sessions", 0)  # stable
    assert query_urn("chatbot-sessions", 1) != a


def test_search_recall_for_offboarding_terms():
    dps = sources.load_data_products()
    hits = entities.search_data_products(dps, "offboarding laudo inspeção reparo")
    slugs = {dp.slug for dp in hits}
    # recall among all ranked matches: the offboarding/termination product must appear
    assert any("offboarding" in s or "termination" in s for s in slugs)


def test_data_product_has_no_product_type():
    dps = sources.load_data_products()
    dp = dps["chatbot-sessions"]
    assert not hasattr(dp, "product_type")
