import pytest
from tars_evals.datahub_mock import execute_datahub_gql, sources
from tars_evals.datahub_mock.entities import DataProduct, dataset_urn
from tars_evals.datahub_mock.schema import datahub_schema

SEARCH = (
    "query($q:String!,$types:[EntityType!],$start:Int,$count:Int){"
    "searchAcrossEntities(input:{query:$q,types:$types,start:$start,count:$count})"
    "{total searchResults{entity{urn type ... on DataProduct{properties{name}}}}}}"
)

SYNTHETIC_URN = "urn:li:dataProduct:synthetic-pagination"

NESTED_ENTITIES = (
    "query($urns:[String!]!,$query:String,$types:[EntityType!],$start:Int,$count:Int){"
    "entities(urns:$urns){... on DataProduct{"
    "entities(input:{query:$query,types:$types,start:$start,count:$count})"
    "{total searchResults{entity{urn}}}}}}"
)


@pytest.fixture
def synthetic_data_product(monkeypatch):
    product = DataProduct(
        slug="synthetic-pagination",
        name="Synthetic Pagination",
        description="Deterministic nested pagination fixture",
        datasets=[
            ("synthetic", f"invoice_{index:02d}" if index < 5 else f"table_{index:02d}")
            for index in range(25)
        ],
        search_text="synthetic pagination",
    )
    monkeypatch.setattr(sources, "load_data_products", lambda: {product.slug: product})
    monkeypatch.setattr(sources, "column_index", lambda: {})
    datahub_schema.cache_clear()
    yield product
    datahub_schema.cache_clear()


def execute_nested_entities(
    *,
    query="*",
    types=None,
    start=0,
    count=10,
    urn=SYNTHETIC_URN,
):
    """Run nested DataProduct.entities through real GraphQL resolver wiring."""
    out = execute_datahub_gql(
        NESTED_ENTITIES,
        {
            "urns": [urn],
            "query": query,
            "types": types,
            "start": start,
            "count": count,
        },
    )
    assert "errors" not in out, out.get("errors")
    return out["data"]["entities"][0]["entities"]


def test_search_returns_matching_data_product():
    out = execute_datahub_gql(
        SEARCH, {"q": "chatbot", "types": ["DATA_PRODUCT"], "start": 0, "count": 10}
    )
    assert "errors" not in out, out.get("errors")
    urns = [
        r["entity"]["urn"] for r in out["data"]["searchAcrossEntities"]["searchResults"]
    ]
    assert any(u == "urn:li:dataProduct:chatbot-sessions" for u in urns)


def test_hydrate_data_product_exposes_golden_query_statement():
    q = (
        '{entities(urns:["urn:li:dataProduct:chatbot-sessions"]){urn type '
        "... on DataProduct{properties{name} structuredProperties{properties{"
        "valueEntities{urn type ... on QueryEntity{properties{name "
        "statement{value language}}}}}}}}}"
    )
    out = execute_datahub_gql(q, None)
    assert "errors" not in out, out.get("errors")
    dp = out["data"]["entities"][0]
    props = dp["structuredProperties"]["properties"]
    stmts = [
        ve["properties"]["statement"]["value"]
        for p in props
        for ve in p["valueEntities"]
        if ve.get("properties", {}).get("statement")
    ]
    assert any("select" in s.lower() for s in stmts)


def test_hydrate_dataset_returns_schema_fields():
    urn = (
        "urn:li:dataset:(urn:li:dataPlatform:trino,"
        "hive.dw_offboarding.obt_offboarding,PROD)"
    )
    q = (
        '{entities(urns:["' + urn + '"]){urn type ... on Dataset{'
        "schemaMetadata{fields{fieldPath nativeDataType description}}}}}"
    )
    out = execute_datahub_gql(q, None)
    assert "errors" not in out, out.get("errors")
    fields = out["data"]["entities"][0]["schemaMetadata"]["fields"]
    assert fields and all("fieldPath" in f for f in fields)


def test_invalid_field_raises_graphql_error():
    # DataHub rejects customProperties on searchResults DataProduct fragments;
    # a real schema reproduces that as an error, keeping tars's behavior realistic.
    bad = (
        '{searchAcrossEntities(input:{query:"chatbot",types:[DATA_PRODUCT]})'
        "{searchResults{entity{... on DataProduct{properties{bogusField}}}}}}"
    )
    out = execute_datahub_gql(bad, None)
    assert "errors" in out


def test_full_hydrate_datasets_fragment_validates():
    # The complete DatasetAnalysisDetails fragment (lineage aliases + assertions
    # + tags + glossaryTerms) must resolve without a GraphQL error — this is the
    # `analysis`/`full` profile Phase-2 query verbatim from DATAHUB.md.
    urn = (
        "urn:li:dataset:(urn:li:dataPlatform:trino,"
        "hive.dw_offboarding.obt_offboarding,PROD)"
    )
    q = (
        "query HydrateDatasets($urns:[String!]!){entities(urns:$urns){urn type "
        "... on Dataset{properties{name description qualifiedName} platform{name} "
        "schemaMetadata{fields{fieldPath nativeDataType description}} "
        "editableSchemaMetadata{editableSchemaFieldInfo{fieldPath description}} "
        "lineageUpstream: lineage(input:{direction:UPSTREAM,start:0,count:5}){total "
        "relationships{type entity{urn type ... on Dataset{properties{name} platform{name}}}}} "
        "lineageDownstream: lineage(input:{direction:DOWNSTREAM,start:0,count:5}){total "
        "relationships{type entity{urn type}}} "
        "assertions(start:0,count:20){total assertions{urn info{datasetAssertion{nativeType "
        "fields{path} nativeParameters{key value}}} runEvents(limit:1,status:COMPLETE){runEvents{"
        "timestampMillis result{type nativeResults{key value}}}}}} "
        "tags{tags{tag{urn properties{name description}}}} "
        "glossaryTerms{terms{term{urn properties{name definition}}}}}}}"
    )
    out = execute_datahub_gql(q, {"urns": [urn]})
    assert "errors" not in out, out.get("errors")
    ds = out["data"]["entities"][0]
    assert ds["schemaMetadata"]["fields"]
    assert ds["lineageUpstream"]["total"] == 0


def test_dataset_root_field_and_dataset_search():
    # dataset(urn:) root (lineage/assertion expansion) + DATASET searchAcross.
    urn = (
        "urn:li:dataset:(urn:li:dataPlatform:trino,"
        "hive.dw_offboarding.obt_offboarding,PROD)"
    )
    out = execute_datahub_gql(
        '{dataset(urn:"' + urn + '"){urn schemaMetadata{fields{fieldPath}}}}', None
    )
    assert "errors" not in out, out.get("errors")
    assert out["data"]["dataset"]["urn"] == urn

    ds_search = execute_datahub_gql(
        '{searchAcrossEntities(input:{query:"obt_offboarding",types:[DATASET],count:3})'
        "{total searchResults{entity{urn type ... on Dataset{properties{qualifiedName}}}}}}",
        None,
    )
    assert "errors" not in ds_search, ds_search.get("errors")
    assert ds_search["data"]["searchAcrossEntities"]["total"] >= 1


def _search_urns(query: str, types: list[str], *, start: int, count: int) -> tuple[int, list[str]]:
    out = execute_datahub_gql(
        SEARCH, {"q": query, "types": types, "start": start, "count": count}
    )
    assert "errors" not in out, out.get("errors")
    block = out["data"]["searchAcrossEntities"]
    urns = [r["entity"]["urn"] for r in block["searchResults"]]
    return block["total"], urns


def test_data_product_search_paginates_with_full_total():
    total_all, full = _search_urns(
        "offboarding", ["DATA_PRODUCT"], start=0, count=1000
    )
    assert total_all >= 2, "need ≥2 matches to exercise pagination"
    assert len(full) == total_all

    total_p0, page0 = _search_urns(
        "offboarding", ["DATA_PRODUCT"], start=0, count=1
    )
    assert total_p0 == total_all
    assert page0 == [full[0]]

    total_p1, page1 = _search_urns(
        "offboarding", ["DATA_PRODUCT"], start=1, count=1
    )
    assert total_p1 == total_all
    assert page1 == [full[1]]
    assert page0[0] != page1[0]


def test_data_product_search_count_zero_returns_no_rows():
    total_all, _ = _search_urns(
        "offboarding", ["DATA_PRODUCT"], start=0, count=1000
    )
    assert total_all >= 1
    total0, urns = _search_urns(
        "offboarding", ["DATA_PRODUCT"], start=0, count=0
    )
    assert total0 == total_all
    assert urns == []


def test_dataset_search_paginates_with_full_total():
    # Broad token that hits multiple hive tables across products.
    total_all, full = _search_urns("fact", ["DATASET"], start=0, count=1000)
    assert total_all >= 3, "need ≥3 dataset matches to exercise pagination"
    assert len(full) == total_all

    total_p0, page0 = _search_urns("fact", ["DATASET"], start=0, count=2)
    assert total_p0 == total_all
    assert page0 == full[:2]

    total_p1, page1 = _search_urns("fact", ["DATASET"], start=2, count=2)
    assert total_p1 == total_all
    assert page1 == full[2:4]
    assert set(page0).isdisjoint(page1)


def test_dataset_search_count_zero_returns_no_rows():
    total_all, _ = _search_urns("obt_offboarding", ["DATASET"], start=0, count=100)
    assert total_all >= 1
    total0, urns = _search_urns(
        "obt_offboarding", ["DATASET"], start=0, count=0
    )
    assert total0 == total_all
    assert urns == []


def test_nested_data_product_entities_paginate():
    q = (
        "query($urns:[String!]!,$start:Int,$count:Int){"
        "entities(urns:$urns){... on DataProduct{"
        "entities(input:{start:$start,count:$count})"
        "{total searchResults{entity{urn}}}}}}"
    )
    urn = "urn:li:dataProduct:chatbot-sessions"
    full = execute_datahub_gql(
        q, {"urns": [urn], "start": 0, "count": 100}
    )
    assert "errors" not in full, full.get("errors")
    block = full["data"]["entities"][0]["entities"]
    total = block["total"]
    assert total >= 2, "chatbot-sessions must expose ≥2 nested datasets"
    all_urns = [r["entity"]["urn"] for r in block["searchResults"]]

    page0 = execute_datahub_gql(q, {"urns": [urn], "start": 0, "count": 1})
    assert "errors" not in page0, page0.get("errors")
    p0 = page0["data"]["entities"][0]["entities"]
    assert p0["total"] == total
    assert [r["entity"]["urn"] for r in p0["searchResults"]] == [all_urns[0]]

    page1 = execute_datahub_gql(q, {"urns": [urn], "start": 1, "count": 1})
    assert "errors" not in page1, page1.get("errors")
    p1 = page1["data"]["entities"][0]["entities"]
    assert p1["total"] == total
    assert [r["entity"]["urn"] for r in p1["searchResults"]] == [all_urns[1]]

    empty = execute_datahub_gql(q, {"urns": [urn], "start": 0, "count": 0})
    assert "errors" not in empty, empty.get("errors")
    pe = empty["data"]["entities"][0]["entities"]
    assert pe["total"] == total
    assert pe["searchResults"] == []


def test_nested_data_product_entities_omitted_count_defaults_to_10(
    synthetic_data_product,
):
    # DataHub SearchInput parity: omitted count → 10, total stays full match count.
    q = (
        '{entities(urns:["' + SYNTHETIC_URN + '"]){... on DataProduct{'
        "entities(input:{start:0})"
        "{total searchResults{entity{urn}}}}}}"
    )
    out = execute_datahub_gql(q, None)
    assert "errors" not in out, out.get("errors")
    block = out["data"]["entities"][0]["entities"]
    assert block["total"] == 25
    assert len(block["searchResults"]) == 10
    expected = [
        dataset_urn("synthetic", f"invoice_{i:02d}" if i < 5 else f"table_{i:02d}")
        for i in range(10)
    ]
    assert [r["entity"]["urn"] for r in block["searchResults"]] == expected


def test_hydrate_index_nested_entities_count_20_returns_page(synthetic_data_product):
    # Canonical TARS HydrateIndex nested breadth (DATAHUB.md): start:0, count:20.
    q = (
        "query HydrateIndex($urns:[String!]!){entities(urns:$urns){urn type "
        "... on DataProduct{properties{name numAssets} "
        "entities(input:{query:\"*\",types:[DATASET],start:0,count:20})"
        "{total searchResults{entity{urn type "
        "... on Dataset{properties{name qualifiedName}}}}}}}}"
    )
    out = execute_datahub_gql(q, {"urns": [SYNTHETIC_URN]})
    assert "errors" not in out, out.get("errors")
    block = out["data"]["entities"][0]["entities"]
    assert block["total"] == 25
    assert len(block["searchResults"]) == 20
    expected = [
        dataset_urn("synthetic", f"invoice_{i:02d}" if i < 5 else f"table_{i:02d}")
        for i in range(20)
    ]
    assert [r["entity"]["urn"] for r in block["searchResults"]] == expected


def test_nested_entities_filter_query_before_pagination(synthetic_data_product):
    result = execute_nested_entities(
        query="invoice",
        types=["DATASET"],
        start=0,
        count=2,
    )
    assert result["total"] == 5
    assert len(result["searchResults"]) == 2
    assert all("invoice_" in row["entity"]["urn"] for row in result["searchResults"])


def test_nested_entities_non_dataset_types_return_empty(synthetic_data_product):
    result = execute_nested_entities(
        query="*",
        types=["DATA_PRODUCT"],
        start=0,
        count=20,
    )
    assert result == {"total": 0, "searchResults": []}


def test_nested_entities_star_query_returns_all_before_pagination(
    synthetic_data_product,
):
    result = execute_nested_entities(
        query="*",
        types=["DATASET"],
        start=0,
        count=100,
    )
    assert result["total"] == 25
    assert len(result["searchResults"]) == 25


def test_nested_entities_omitted_types_return_all_before_pagination(
    synthetic_data_product,
):
    # Omitted types: GraphQL query with no types field in the input.
    q = (
        '{entities(urns:["' + SYNTHETIC_URN + '"]){... on DataProduct{'
        'entities(input:{query:"*",start:0,count:100})'
        "{total searchResults{entity{urn}}}}}}"
    )
    out = execute_datahub_gql(q, None)
    assert "errors" not in out, out.get("errors")
    block = out["data"]["entities"][0]["entities"]
    assert block["total"] == 25
    assert len(block["searchResults"]) == 25
