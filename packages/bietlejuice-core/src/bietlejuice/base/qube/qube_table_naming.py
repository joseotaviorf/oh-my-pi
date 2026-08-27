"""Shared QUBE output table naming (build + register must stay aligned)."""


def qube_clean_spec_name(entity: str, name: str) -> str:
    """Strip redundant entity prefix from spec name (mirrors build_dimension/build_measure)."""
    if name.startswith(f"{entity}_"):
        return name[len(entity) + 1 :]
    return name


def qube_output_base_table_name(entity: str, name: str) -> str:
    """Base table name without window suffix, e.g. visit_business_context."""
    clean_name = qube_clean_spec_name(entity, name)
    return f"{entity}_{clean_name}"


def qube_windowed_table_name(entity: str, name: str, window_days: int) -> str:
    """Physical Delta table name for a window, e.g. visit_business_context_28d."""
    return f"{qube_output_base_table_name(entity, name)}_{window_days}d"


def qube_validation_trino_table_name(
    prod_database: str, windowed_table_name: str
) -> str:
    """Trino table name in cluster_validation, e.g. qube_dimensions___visit_business_context_28d."""
    return f"{prod_database}___{windowed_table_name}"
