"""Local DataHub backend public entrypoint.

`execute_datahub_gql` runs a GraphQL query against the in-process
`graphql-core` schema (see `schema.py`) and returns the DataHub-shaped
envelope: `{"data": {...}}` and/or `{"errors": [...]}`.
"""

from __future__ import annotations

from graphql import graphql_sync

from tars_evals.datahub_mock.schema import datahub_schema


def execute_datahub_gql(query: str, variables: dict | None) -> dict:
    """Execute a DataHub GraphQL query against the local schema. Returns the
    DataHub-shaped envelope: `{"data": {...}}` and/or `{"errors": [...]}`."""
    result = graphql_sync(datahub_schema(), query, variable_values=variables or {})
    out: dict = {}
    if result.data is not None:
        out["data"] = result.data
    if result.errors:
        out["errors"] = [{"message": e.message} for e in result.errors]
    return out
