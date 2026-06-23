"""Constants for TARS entity self-service sync pipeline."""

from __future__ import annotations

TARS_ENTITY_TAG = "tars-entity"
TARS_ENTITY_TAG_URN = "urn:li:tag:tars-entity"

TARS_METRICS_TAG = "tars-metrics"
TARS_METRICS_TAG_URN = "urn:li:tag:tars-metrics"

DATA_PRODUCT_TYPE_DOMAIN = "domain"
DATA_PRODUCT_TYPE_METRIC = "metric"

STRUCTURED_PROP_DOMAIN_URN = "br.com.quintoandar.datahub.tars_entity.domain_urn"
STRUCTURED_PROP_DATA_PRODUCT_ID = (
    "br.com.quintoandar.datahub.tars_entity.data_product_id"
)
STRUCTURED_PROP_PRIMARY_DATASETS = (
    "br.com.quintoandar.datahub.tars_entity.primary_datasets"
)
STRUCTURED_PROP_GOLDEN_QUERY_URN = (
    "br.com.quintoandar.datahub.tars_entity.golden_query_stable_urn"
)
STRUCTURED_PROP_GLOSSARY_PARENT = (
    "br.com.quintoandar.datahub.tars_entity.glossary_parent_node_urn"
)
STRUCTURED_PROP_SYNC_STATUS = "br.com.quintoandar.datahub.tars_entity.sync_status"

GITHUB_REPO = "quintoandar/bi-etl-ejuice"
GITHUB_DEFAULT_BRANCH = "master"
MD_OUTPUT_DIR = "docs/llm_context/business_entities"
MD_OUTPUT_DIR_METRICS = "docs/llm_context/metric_entities"
YAML_OUTPUT_DIR = "dags/governance/datahub_business_context/datahub_entities"

REQUIRED_MD_SECTIONS = (
    "overview",
    "glossary",
    "tables",
    "golden",
)

DELIVERY_MODE_GITOPS = "gitops"
DELIVERY_MODE_DIRECT = "direct"

SYNC_STATE_FILENAME = ".tars_entity_sync_state.json"

# Shared golden-query structured property (one SP for all Data Products)
STRUCTURED_PROP_GOLDEN_QUERY = "br.com.quintoandar.datahub.data_product.golden_query"

# Lifecycle stage structured property for Data Products
STRUCTURED_PROP_LIFECYCLE_STAGE = (
    "br.com.quintoandar.datahub.data_product.lifecycle_stage"
)
LIFECYCLE_STAGE_PROD = "prod"
LIFECYCLE_STAGE_DRAFT = "draft"
LIFECYCLE_STAGE_REVIEW = "review"
LIFECYCLE_STAGE_DEPRECATED = "deprecated"
_LIFECYCLE_STAGES_ALLOWED = frozenset(
    {
        LIFECYCLE_STAGE_DRAFT,
        LIFECYCLE_STAGE_REVIEW,
        LIFECYCLE_STAGE_PROD,
        LIFECYCLE_STAGE_DEPRECATED,
    }
)
