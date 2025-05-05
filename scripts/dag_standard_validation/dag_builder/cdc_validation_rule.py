from scripts.dag_standard_validation.dag_builder.base_dag_builder_standard_validation_rule import (
    BaseDagBuilderStandardValidationRule,
)


class CDCValidationRule(BaseDagBuilderStandardValidationRule):
    """
    Validation rule to check if a DAG is a database ingestion without CDC. We should only be using
    CDC for database ingestion.
    """

    @classmethod
    def is_valid(cls, dag_declaration: dict) -> bool:
        is_database_ingestion_without_cdc = dag_declaration["workflow"].get("type") in (
            "database_pull",
            "database_pull_delta",
        )
        return (
            not is_database_ingestion_without_cdc
            or dag_declaration["workflow"].get("database_type")
            == "mongo"  # We don't have CDC for MongoDB
        )

    @classmethod
    def get_validation_name(cls) -> str:
        return "database_ingestion_without_cdc"

    @classmethod
    def get_validation_description(cls) -> str:
        return "The DAG is a database ingestion without CDC. Use the workflow type 'cdc' instead of 'database_pull' or 'database_pull_delta'"
