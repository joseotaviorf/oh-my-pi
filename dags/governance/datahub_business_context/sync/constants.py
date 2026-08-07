"""Constants shared by entity Markdown validation and Luigi CI."""

from __future__ import annotations

DATA_PRODUCT_TYPE_DOMAIN = "domain"
DATA_PRODUCT_TYPE_METRIC = "metric"

GITHUB_REPO = "quintoandar/bi-etl-ejuice"

REQUIRED_MD_SECTIONS = (
    "overview",
    "glossary",
    "tables",
    "golden",
)

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
