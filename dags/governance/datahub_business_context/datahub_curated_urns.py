"""Pydantic model for Data Product / golden-query URNs in ``full_curated_datahub_bundle`` presets.

Business copy and table registries live in sibling ``*_bundle.py`` modules; this file stays
GraphQL-agnostic and entity-name free.
"""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, ConfigDict, Field, computed_field, field_validator


def structured_property_urn(qname: str) -> str:
    return f"urn:li:structuredProperty:{qname.strip()}"


class DataHubCuratedUrns(BaseModel):
    """URNs and link targets for a full curated Data Product push (sidebar SP, batchSet, etc.)."""

    model_config = ConfigDict(extra="ignore", str_strip_whitespace=True)

    data_product_id: str = Field(
        description="Data Product slug → urn:li:dataProduct:{id}"
    )
    domain_urn: str
    glossary_parent_node_urn: str

    golden_query_urn: str = Field(
        description=(
            "Stable Query entity URN after first successful createQuery "
            "(override when recreating the query)."
        ),
    )
    golden_query_subject_urns: list[str] = Field(default_factory=list)

    golden_query_structured_property_qualified_name: str
    legacy_golden_query_structured_property_qualified_names_to_drop: list[str] = Field(
        default_factory=list,
    )

    data_product_attached_glossary_term_urns: list[str] = Field(default_factory=list)

    documentation_github_url: str
    golden_query_discovery_link_removal_label: str

    dataset_resource_urns: list[str] = Field(default_factory=list)

    entity_type_data_product: str = Field(
        default="urn:li:entityType:datahub.dataProduct",
    )
    entity_type_query: str = Field(default="urn:li:entityType:datahub.query")
    value_type_datahub_urn: str = Field(default="urn:li:dataType:datahub.urn")

    @field_validator(
        "golden_query_subject_urns",
        "data_product_attached_glossary_term_urns",
        "dataset_resource_urns",
    )
    @classmethod
    def _sort_unique_nonempty(cls, rows: list[str]) -> list[str]:
        cleaned = [str(x).strip() for x in rows if str(x).strip()]
        return sorted(set(cleaned))

    @field_validator(
        "legacy_golden_query_structured_property_qualified_names_to_drop",
    )
    @classmethod
    def _strip_qualnames(cls, rows: list[str]) -> list[str]:
        return sorted({str(x).strip() for x in rows if str(x).strip()})

    @computed_field(repr=False)  # type: ignore[prop-decorator]
    @property
    def data_product_urn(self) -> str:
        return f"urn:li:dataProduct:{self.data_product_id}"

    @computed_field(repr=False)  # type: ignore[prop-decorator]
    @property
    def golden_query_structured_property_urn(self) -> str:
        return structured_property_urn(
            self.golden_query_structured_property_qualified_name
        )

    @computed_field(repr=False)  # type: ignore[prop-decorator]
    @property
    def legacy_structured_property_urns_to_drop(self) -> frozenset[str]:
        return frozenset(
            structured_property_urn(qname)
            for qname in self.legacy_golden_query_structured_property_qualified_names_to_drop
        )

    def golden_query_ui_summary_url(self, ui_origin: str) -> str:
        base = ui_origin.strip().rstrip("/")
        return f"{base}/query/{self.golden_query_urn}"


# DataHub metamodel URNs shared by every product (sidebar “golden query” SP scaffolding).
STRUCTURED_PROPERTY_ENTITY_TYPE_DATA_PRODUCT = "urn:li:entityType:datahub.dataProduct"
STRUCTURED_PROPERTY_ENTITY_TYPE_QUERY = "urn:li:entityType:datahub.query"
STRUCTURED_PROPERTY_VALUE_TYPE_URN_POINTER = "urn:li:dataType:datahub.urn"


def load_curated_urns_from_spec(
    spec: dict[str, Any],
    baseline_kwargs: dict[str, Any],
) -> DataHubCuratedUrns:
    """YAML ``uris`` (+ root domain / glossary anchors) merged into bundle-supplied URNs."""

    base = DataHubCuratedUrns(**baseline_kwargs)
    updates: dict[str, Any] = {}
    raw_uris = spec.get("uris")
    if isinstance(raw_uris, dict):
        updates.update({k: v for k, v in raw_uris.items() if v is not None})
    if spec.get("domain_urn"):
        updates["domain_urn"] = str(spec["domain_urn"])
    if spec.get("glossary_parent_node_urn"):
        updates["glossary_parent_node_urn"] = str(spec["glossary_parent_node_urn"])
    return (
        DataHubCuratedUrns(**{**base.model_dump(mode="python"), **updates})
        if updates
        else base
    )
