from bietlejuice.base.databricks.cluster_permission_enum import ClusterPermissionEnum
from bietlejuice.base.databricks.databricks_group_name_enum import DatabricksGroupNameEnum

VESPUCIO_PACKAGE_NAME = "vespucio"

DATABRICKS_CLUSTER_ACCESS_CONTROL_LIST = [
    {
        "group_name": DatabricksGroupNameEnum.ANALYTICS_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    },
    {
        "group_name": DatabricksGroupNameEnum.SOFTWARE_ENGINEERS,
        "permission_level": ClusterPermissionEnum.MANAGE,
    },
]

BASE_ALIAS_CLASSIFIEDS_PARAMS = [
    "--input_condo_compound=vespucio_prod_delta.condo_compounds",
    "--input_house_compound=vespucio_prod_delta.house_compounds",
    "--input_listing_compound=vespucio_prod_delta.listings",
    "--input_zordominium_compound=zordominium_vespucio_plugin.zordominium_official_condos",
    "--input_navent_source_table=vespucio_sources_delta.source_navent_houses",
    "--input_classified_house_id_table=vespucio_classifieds.classifieds_house_id",
    "--input_navent_publisher_reputation_table=vespucio_sources_delta.source_navent_publisher_reputation",
    "--input_ebdb_region_table=datalake_ebdb_clean.region",
    "--input_ebdb_state_table=datalake_ebdb_clean.state",
    "--input_ebdb_country_table=datalake_ebdb_clean.country",
    "--input_publisher_scope_table=vespucio_alias.alias_publisher_scope",
    "--output_alias_compound=vespucio_alias.alias_classifieds_compound",
]

BASE_ALIAS_CLASSIFIEDS_PUBLISHER_PARAMS = [
    "--input_alias_classifieds_table=vespucio_alias.alias_classifieds_compound",
    "--output_published_listings_table=vespucio_alias.alias_published_listings",
    "--logging_table=vespucio_alias.alias_publish_log",
    "--security_protocol=SASL_SSL",
    "--credentials_secret_scope=quintoandar",
    "--credentials_secret_key=VESPUCIO_CONFLUENT_CREDENTIALS",
    "--logging_retention_days=30",
    "--running_mode=prod",
]
