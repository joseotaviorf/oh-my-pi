"""Core data model for the local DataHub backend.

Defines the DataProduct dataclass and URN helpers (data_product_urn,
dataset_urn, parse_dataset_urn, query_urn) used by sources.py and the
eval tool layer. No DataHub SDK dependency — everything is plain Python.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass, field


@dataclass
class DataProduct:
    slug: str
    name: str
    description: str
    glossary_terms: list = field(default_factory=list)  # list of (name, description)
    datasets: list = field(default_factory=list)  # list of (schema, table)
    golden_queries: list = field(default_factory=list)  # list of GoldenQuery
    search_text: str = ""


def data_product_urn(slug: str) -> str:
    return f"urn:li:dataProduct:{slug}"


def dataset_urn(schema: str, table: str) -> str:
    return f"urn:li:dataset:(urn:li:dataPlatform:trino,hive.{schema}.{table},PROD)"


def parse_dataset_urn(urn: str) -> tuple[str, str] | None:
    # urn:li:dataset:(urn:li:dataPlatform:trino,hive.<schema>.<table>,PROD)
    try:
        inner = urn.split("(", 1)[1].rsplit(")", 1)[0]
        name = inner.split(",")[1]  # hive.<schema>.<table>
    except (IndexError, ValueError):
        return None
    parts = name.strip().split(".")
    if len(parts) >= 3 and parts[0] == "hive":
        return parts[1], ".".join(parts[2:])
    return None


def query_urn(slug: str, i: int) -> str:
    seed = slug if i == 0 else f"{slug}:{i}"
    return f"urn:li:query:{uuid.uuid5(uuid.NAMESPACE_URL, seed)}"


def build_data_product(slug: str, parsed) -> DataProduct:
    glossary = [(t.name, t.description) for t in parsed.glossary_terms]
    search_parts = [slug.replace("-", " "), parsed.title, parsed.overview]
    search_parts += [f"{n} {d}" for n, d in glossary]
    search_parts += [
        f"{s} {t}" for s, t in parsed.datasets
    ]  # golden-query subject tables aid recall
    return DataProduct(
        slug=slug,
        name=parsed.title,
        description=parsed.overview,
        glossary_terms=glossary,
        datasets=list(parsed.datasets),
        golden_queries=list(parsed.golden_queries),
        search_text=" ".join(search_parts).lower(),
    )


def search_data_products(
    dps: dict[str, DataProduct], query: str
) -> list[DataProduct]:
    """Return all matches ranked by score (caller paginates)."""
    tokens = [t for t in query.lower().split() if t]
    scored = []
    for slug in sorted(dps):  # deterministic tie-break
        dp = dps[slug]
        score = sum(1 for t in tokens if t in dp.search_text)
        if score > 0:
            scored.append((score, dp))
    scored.sort(key=lambda pair: -pair[0])
    return [dp for _, dp in scored]
