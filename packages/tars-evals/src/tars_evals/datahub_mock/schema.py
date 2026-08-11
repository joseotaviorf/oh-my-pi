"""The graphql-core schema for the local DataHub backend.

The SDL covers the full documented tars DataHub contract (docs/DATAHUB.md), so
any field tars requests that is NOT in the SDL fails loudly as a GraphQL error
(mirroring DataHub's ValidationError) rather than silently returning null.
Resolvers return plain dicts keyed as the SDL fields for graphql-core's default
resolver; the `Entity` interface's resolve_type reads each dict's `"type"`.
"""

from __future__ import annotations

import functools

from graphql import GraphQLSchema, build_schema

from tars_evals.datahub_mock import entities as E
from tars_evals.datahub_mock import sources

_SDL = """
enum EntityType { DATA_PRODUCT DATASET GLOSSARY_TERM GLOSSARY_NODE CONTAINER CORP_USER CORP_GROUP TAG DOMAIN }
enum LineageDirection { UPSTREAM DOWNSTREAM }
enum AssertionRunStatus { COMPLETE }

type KV { key: String value: String }
type NamedProps { name: String description: String qualifiedName: String definition: String numAssets: Int source: String externalUrl: String }
type DPProps { name: String description: String externalUrl: String numAssets: Int customProperties: [KV] }
type Platform { name: String }
type StatementValue { value: String language: String }
type ActorProps { displayName: String fullName: String email: String }
type Actor { urn: String username: String properties: ActorProps }
type Audit { time: String actor: Actor }
type IMAudit { time: String actor: String }
type QueryProps { name: String description: String source: String statement: StatementValue createdOn: Audit lastModified: Audit }
type SubjectDataset { urn: String properties: NamedProps platform: Platform }
type Subject { dataset: SubjectDataset }
type SchemaField { fieldPath: String nativeDataType: String description: String }
type SchemaMetadata { fields: [SchemaField] }
type EditableField { fieldPath: String description: String }
type EditableSchemaMetadata { editableSchemaFieldInfo: [EditableField] }
type StringValue { stringValue: String }
type NumberValue { numberValue: Float }
union PropValue = StringValue | NumberValue
type SPDef { qualifiedName: String displayName: String description: String }
type SProperty { urn: String definition: SPDef }
type SPropEntry { structuredProperty: SProperty values: [PropValue] valueEntities: [Entity] }
type StructuredProperties { properties: [SPropEntry] }
type DomainProps { name: String description: String }
type DomainRef { urn: String properties: DomainProps }
type DomainWrap { domain: DomainRef }
type OwnershipTypeInfo { name: String }
type OwnershipType { info: OwnershipTypeInfo }
type Owner { owner: Entity type: String ownershipType: OwnershipType }
type Ownership { owners: [Owner] }
type TagProps { name: String description: String }
type TagRef { urn: String properties: TagProps }
type TagEntry { tag: TagRef }
type Tags { tags: [TagEntry] }
type TermProps { name: String definition: String }
type TermRef { urn: String properties: TermProps }
type TermEntry { term: TermRef }
type GlossaryTerms { terms: [TermEntry] }
type IMElement { url: String label: String description: String created: IMAudit }
type InstitutionalMemory { elements: [IMElement] }
type LineageRel { type: String entity: Entity }
type LineageResult { total: Int relationships: [LineageRel] }
type AssertionFieldPath { path: String }
type DatasetAssertion { nativeType: String fields: [AssertionFieldPath] nativeParameters: [KV] }
type AssertionInfo { datasetAssertion: DatasetAssertion }
type NativeResult { key: String value: String }
type RunEventResult { type: String nativeResults: [NativeResult] }
type RunEvent { timestampMillis: String result: RunEventResult }
type RunEvents { runEvents: [RunEvent] }
type Assertion { urn: String info: AssertionInfo runEvents(limit: Int, status: AssertionRunStatus): RunEvents }
type Assertions { total: Int assertions: [Assertion] }
input SearchInput { query: String types: [EntityType] start: Int count: Int }
input LineageInput { direction: LineageDirection start: Int count: Int }

interface Entity { urn: String type: String }
type CorpUser implements Entity { urn: String type: String username: String properties: ActorProps }
type CorpGroup implements Entity { urn: String type: String properties: ActorProps }
type DataProduct implements Entity {
  urn: String type: String
  properties: DPProps
  domain: DomainWrap
  ownership: Ownership
  tags: Tags
  glossaryTerms: GlossaryTerms
  institutionalMemory: InstitutionalMemory
  structuredProperties: StructuredProperties
  entities(input: SearchInput): SearchAcross
}
type Dataset implements Entity {
  urn: String type: String
  properties: NamedProps
  platform: Platform
  schemaMetadata: SchemaMetadata
  editableSchemaMetadata: EditableSchemaMetadata
  lineage(input: LineageInput): LineageResult
  assertions(start: Int, count: Int): Assertions
  tags: Tags
  glossaryTerms: GlossaryTerms
}
type QueryEntity implements Entity {
  urn: String type: String
  properties: QueryProps
  subjects: [Subject]
}
type SearchResult { entity: Entity }
type SearchAcross { total: Int searchResults: [SearchResult] }
type Query {
  searchAcrossEntities(input: SearchInput): SearchAcross
  entities(urns: [String!]!): [Entity]
  dataset(urn: String!): Dataset
}
"""

_TYPE_BY_DISCRIMINATOR = {
    "DATA_PRODUCT": "DataProduct",
    "DATASET": "Dataset",
    "QUERY": "QueryEntity",
    "CORP_USER": "CorpUser",
    "CORP_GROUP": "CorpGroup",
}


def _resolve_entity_type(obj, info, type_):
    return _TYPE_BY_DISCRIMINATOR[obj["type"]]


def _resolve_prop_value(obj, info, type_):
    return "StringValue" if "stringValue" in obj else "NumberValue"


def _subjects_for(gq, dp):
    # Prefer subjects parsed from the golden SQL; fall back to the DP's datasets.
    parser = sources._document_parser()
    subs = parser.extract_subjects_from_sql(gq.sql)
    return subs or dp.datasets


def _dp_dict(dp):
    """DataProduct → resolver dict. Golden queries become QueryEntity
    valueEntities under the golden_query structured property; the DP's datasets
    become the nested `entities` search block as full Dataset entities."""
    value_entities = []
    for i, gq in enumerate(dp.golden_queries):
        subjects = [
            {
                "dataset": {
                    "urn": E.dataset_urn(s, t),
                    "properties": {
                        "name": f"hive.{s}.{t}",
                        "qualifiedName": f"hive.{s}.{t}",
                    },
                    "platform": {"name": "trino"},
                }
            }
            for (s, t) in _subjects_for(gq, dp)
        ]
        value_entities.append(
            {
                "type": "QUERY",
                "urn": E.query_urn(dp.slug, i),
                "properties": {
                    "name": gq.name,
                    "description": gq.description,
                    "source": "MANUAL",
                    "statement": {"value": gq.sql, "language": "SQL"},
                    "createdOn": None,
                    "lastModified": None,
                },
                "subjects": subjects,
            }
        )
    dataset_results = [{"entity": _dataset_dict(s, t)} for (s, t) in dp.datasets]
    return {
        "type": "DATA_PRODUCT",
        "urn": E.data_product_urn(dp.slug),
        "properties": {
            "name": dp.name,
            "description": dp.description,
            "externalUrl": None,
            "numAssets": len(dp.datasets),
            "customProperties": [],
        },
        "domain": {"domain": None},
        "ownership": {"owners": []},
        "tags": {"tags": []},
        "glossaryTerms": {
            "terms": [
                {
                    "term": {
                        "urn": f"urn:li:glossaryTerm:{n}",
                        "properties": {"name": n, "definition": d},
                    }
                }
                for n, d in dp.glossary_terms
            ]
        },
        "institutionalMemory": {"elements": []},
        "structuredProperties": {
            "properties": [
                {
                    "structuredProperty": {
                        "urn": "urn:li:structuredProperty:br.com.quintoandar.datahub.data_product.golden_query",
                        "definition": {
                            "qualifiedName": "br.com.quintoandar.datahub.data_product.golden_query",
                            "displayName": "Golden Query",
                            "description": None,
                        },
                    },
                    "values": [],
                    "valueEntities": value_entities,
                }
            ]
        },
        "_dataset_results": dataset_results,  # consumed by DataProduct.entities resolver
    }


def _dataset_dict(schema, table):
    fields = sources.column_index().get((schema, table), [])
    return {
        "type": "DATASET",
        "urn": E.dataset_urn(schema, table),
        "properties": {
            "name": f"hive.{schema}.{table}",
            "description": None,
            "qualifiedName": f"hive.{schema}.{table}",
        },
        "platform": {"name": "trino"},
        "schemaMetadata": {"fields": fields},
        "editableSchemaMetadata": {
            "editableSchemaFieldInfo": [
                {"fieldPath": f["fieldPath"], "description": f["description"]}
                for f in fields
            ]
        },
        # Empty-but-valid so lineage/assertion/tag/term selections resolve to
        # nulls tars tolerates (both alias'd lineage selections read this key).
        "lineage": {"total": 0, "relationships": []},
        "assertions": {"total": 0, "assertions": []},
        "tags": {"tags": []},
        "glossaryTerms": {"terms": []},
    }


def _all_dataset_pairs(dps):
    seen, out = set(), []
    for dp in dps.values():
        for pair in dp.datasets:
            if pair not in seen:
                seen.add(pair)
                out.append(pair)
    return out


def _pagination_window(input) -> tuple[int, int]:
    """Resolve SearchInput start/count. ``count=0`` is meaningful (empty page)."""
    raw = input or {}
    start = raw.get("start")
    if start is None:
        start = 0
    count = raw.get("count")
    if count is None:
        count = 10
    return start, count


def _paginate(items, input):
    start, count = _pagination_window(input)
    total = len(items)
    return total, items[start : start + count]


def _filter_nested_datasets(items, input):
    """Filter a DataProduct's nested dataset results by SearchInput query/types.

    Scoped to nested entities only — does not change top-level search ranking.
    """
    raw = input or {}
    types = raw.get("types") or []
    if types and "DATASET" not in types:
        return []

    query = raw.get("query", "") or ""
    tokens = [token for token in query.lower().split() if token and token != "*"]
    if not tokens:
        return items

    filtered = []
    for result in items:
        properties = result["entity"]["properties"]
        haystack = (
            f"{properties.get('qualifiedName', '')} "
            f"{properties.get('name', '')}"
        ).lower()
        if all(token in haystack for token in tokens):
            filtered.append(result)
    return filtered


def _resolve_search(root, info, input):
    dps = sources.load_data_products()
    types = input.get("types") or []
    query = input.get("query", "") or ""
    if "DATASET" in types and "DATA_PRODUCT" not in types:
        # Direct dataset search by table name (tars uses this to resolve a
        # bare table → URN). Recall-oriented, same spirit as DP search.
        toks = [t for t in query.lower().split() if t and t != "*"]
        pairs = _all_dataset_pairs(dps)
        scored = []
        for s, t in pairs:
            hay = f"{s}.{t}".lower()
            score = sum(1 for tk in toks if tk in hay) if toks else 1
            if score > 0:
                scored.append((score, s, t))
        scored.sort(key=lambda x: (-x[0], x[1], x[2]))
        total, page = _paginate(scored, input)
        return {
            "total": total,
            "searchResults": [{"entity": _dataset_dict(s, t)} for _, s, t in page],
        }
    matches = E.search_data_products(dps, query)
    total, page = _paginate(matches, input)
    return {
        "total": total,
        "searchResults": [{"entity": _dp_dict(dp)} for dp in page],
    }


def _resolve_entities(root, info, urns):
    dps = sources.load_data_products()
    dp_dicts = {E.data_product_urn(dp.slug): _dp_dict(dp) for dp in dps.values()}

    query_by_urn = {}
    if any(u.startswith("urn:li:query:") for u in urns):
        for dp_dict_val in dp_dicts.values():
            for prop in dp_dict_val["structuredProperties"]["properties"]:
                for ve in prop["valueEntities"]:
                    query_by_urn[ve["urn"]] = ve

    out = []
    for urn in urns:
        if urn in dp_dicts:
            out.append(dp_dicts[urn])
        elif urn.startswith("urn:li:query:") and urn in query_by_urn:
            out.append(query_by_urn[urn])
        else:
            parsed = E.parse_dataset_urn(urn)
            out.append(_dataset_dict(*parsed) if parsed else None)
    return out


def _resolve_dataset(root, info, urn):
    parsed = E.parse_dataset_urn(urn)
    return _dataset_dict(*parsed) if parsed else None


def _resolve_dp_entities(dp_dict, info, input=None):
    filtered = _filter_nested_datasets(dp_dict["_dataset_results"], input)
    total, page = _paginate(filtered, input)
    return {
        "total": total,
        "searchResults": page,
    }


@functools.cache
def datahub_schema() -> GraphQLSchema:
    schema = build_schema(_SDL)
    schema.query_type.fields["searchAcrossEntities"].resolve = _resolve_search
    schema.query_type.fields["entities"].resolve = _resolve_entities
    schema.query_type.fields["dataset"].resolve = _resolve_dataset
    schema.type_map["DataProduct"].fields["entities"].resolve = _resolve_dp_entities
    schema.type_map["Entity"].resolve_type = _resolve_entity_type
    schema.type_map["PropValue"].resolve_type = _resolve_prop_value
    return schema
