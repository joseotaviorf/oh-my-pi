"""Build DataHub dataset URNs and list platform-specific URN candidates for a table FQN."""


def build_dataset_urn(platform_key: str, dataset_id: str, fabric: str = "PROD") -> str:
    """Full DataHub dataset URN (GraphQL ``dataset(urn: ...)`` / OpenAPI ``/entities``)."""

    return f"urn:li:dataset:(urn:li:dataPlatform:{platform_key},{dataset_id},{fabric})"


def dataset_id_for_platform(
    platform_key: str, database_name: str, table_name: str
) -> str:
    """Dataset id segment inside the URN (after dataPlatform, before fabric).

    - Databricks: ``schema.table`` (no hive. prefix).
    - Trino: ``hive.schema.table`` (hive. prefix on the Hive catalog side).
    """

    db = database_name.strip()
    tbl = table_name.strip()
    if platform_key == "databricks":
        return f"{db}.{tbl}"
    if platform_key == "trino":
        return f"hive.{db}.{tbl}"
    raise ValueError(f"Unsupported DataHub platform for F4-01: {platform_key!r}")


def list_platform_urns_for_fqn(
    database_name: str,
    table_name: str,
    *,
    server_databricks: bool,
    server_trino: bool,
    fabric: str = "PROD",
) -> list[tuple[str, str]]:
    """Return (platform_key, dataset_urn) for each enabled server."""

    out: list[tuple[str, str]] = []
    if server_databricks:
        did = dataset_id_for_platform("databricks", database_name, table_name)
        out.append(("databricks", build_dataset_urn("databricks", did, fabric)))
    if server_trino:
        did = dataset_id_for_platform("trino", database_name, table_name)
        out.append(("trino", build_dataset_urn("trino", did, fabric)))
    return out
