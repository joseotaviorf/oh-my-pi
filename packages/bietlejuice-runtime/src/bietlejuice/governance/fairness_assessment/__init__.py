"""
FAIRness assessment: tiering, checks, table/column description quality, schema vs docs, DataHub GraphQL.
"""

from bietlejuice.governance.fairness_assessment.adapters.columns_metastore import (  # noqa: E501
    resolve_columns_metastore_snapshot,
)
from bietlejuice.governance.fairness_assessment.checks import (
    evaluate_mvp_checks_from_row,
)
from bietlejuice.governance.fairness_assessment.checks.accessible.a1_2_01_access_request_documented import (  # noqa: E501
    check_a1_2_01_access_request_documented,
)
from bietlejuice.governance.fairness_assessment.checks.accessible.a1_2_02_approver_ownership import (  # noqa: E501
    check_a1_2_02_approver_ownership,
)
from bietlejuice.governance.fairness_assessment.checks.accessible.a1_2_03_interim_access_via_contract import (  # noqa: E501
    check_a1_2_03_interim_access_policy_via_contract,
)
from bietlejuice.governance.fairness_assessment.checks.findable.f1_03_addressable_fqn import (  # noqa: E501
    check_f1_03_addressable_fqn,
)
from bietlejuice.governance.fairness_assessment.checks.findable.f4_01_indexed_in_datahub import (  # noqa: E501
    check_f4_01_indexed_in_datahub,
)
from bietlejuice.governance.fairness_assessment.checks.interoperable.i1_02_data_contract_present import (  # noqa: E501
    check_i1_02_data_contract_present,
)
from bietlejuice.governance.fairness_assessment.constants import (
    COLUMNS_DOC,
    COLUMNS_METASTORE,
    DAG_INVENTORY,
    DAG_INVENTORY_DAG_PREFIX,
    DAG_INVENTORY_PRODUCTIVE_LAYERS,
    DATAHUB_CHECK_FAILED,
    DATAHUB_DATASET_FAIR_SIGNALS_QUERY,
    DATAHUB_ENTITY_NOT_FOUND,
    DATAHUB_F4_REASON_HOST_UNCONFIGURED,
    DATAHUB_F4_REASON_NO_CANDIDATE_URNS,
    DATAHUB_FETCH_ERROR,
    DATAHUB_HTTP_ERROR,
    DATAHUB_OWNERSHIP_TYPE_APPROVERS_URN,
    DATAHUB_SP_DATA_CONTRACT_URN,
    DATAHUB_SP_FAIRNESS_CLASSIFICATION_URN,
    DATAHUB_SP_HOW_TO_REQUEST_ACCESS_URN,
    DATAHUB_UNREACHABLE_REASON,
    DATAHUB_URN_DIAG_OK,
    JOB_NAME,
    MVP_IMPLEMENTED_REQUIREMENT_IDS,
    ORG_CHART,
    TABLES_DOC,
    TIERING_RULES_VERSION,
)
from bietlejuice.governance.fairness_assessment.datahub_graphql import (
    _parse_dataset_fair_signals,
    build_dataset_fqn_search_query,
    build_dataset_urn,
    build_fetch_dataset_structured_properties_query,
    build_upsert_structured_property_mutation,
    compute_a1_2_01_how_to_request_access_by_fqn,
    compute_a1_2_02_approvers_by_fqn,
    compute_f4_pass_and_reason_by_fqn,
    compute_has_data_contract_by_fqn,
    compute_i3_lineage_pass_and_totals_by_fqn,
    compute_i3_ownership_pass_by_fqn,
    dataset_id_for_platform,
    dataset_name_from_urn,
    find_matching_dataset_urns,
    fqn_matches,
    list_platform_urns_for_fqn,
    parse_search_result_urns,
    push_classifications,
    resolve_datahub_gms_base_url,
    resolve_datahub_graphql_url,
    resolve_datahub_urn_flags,
    structured_property_rows_from_fetch,
)
from bietlejuice.governance.fairness_assessment.description_quality import (  # noqa: E501
    assess_column_description_quality,
    assess_table_description_quality,
)
from bietlejuice.governance.fairness_assessment.models import (  # noqa: E501
    RequirementResult,
    TableDescriptionQualityResult,
    TierComputationResult,
)
from bietlejuice.governance.fairness_assessment.schema_validation import (  # noqa: E501
    compute_f2_02_and_i1_01_for_fqn,
)
from bietlejuice.governance.fairness_assessment.tiering import (  # noqa: E501
    MVP_TIER2_SCOPED_REQUIREMENT_IDS,
    TIER1_ACTIVE_REQUIREMENT_IDS,
    TIER_1_IDS,
    TIER_ACHIEVED_TO_CLASSIFICATION,
    compute_tier,
    compute_tier_mvp,
    cumulative_ids_for_tier,
    normalize_classification_to_sp_value,
    tier_achieved_to_classification,
)

__all__ = [
    "COLUMNS_DOC",
    "COLUMNS_METASTORE",
    "DAG_INVENTORY",
    "DAG_INVENTORY_DAG_PREFIX",
    "DAG_INVENTORY_PRODUCTIVE_LAYERS",
    "DATAHUB_CHECK_FAILED",
    "DATAHUB_DATASET_FAIR_SIGNALS_QUERY",
    "DATAHUB_ENTITY_NOT_FOUND",
    "DATAHUB_FETCH_ERROR",
    "DATAHUB_F4_REASON_HOST_UNCONFIGURED",
    "DATAHUB_F4_REASON_NO_CANDIDATE_URNS",
    "DATAHUB_HTTP_ERROR",
    "DATAHUB_OWNERSHIP_TYPE_APPROVERS_URN",
    "DATAHUB_SP_DATA_CONTRACT_URN",
    "DATAHUB_SP_FAIRNESS_CLASSIFICATION_URN",
    "DATAHUB_SP_HOW_TO_REQUEST_ACCESS_URN",
    "DATAHUB_UNREACHABLE_REASON",
    "DATAHUB_URN_DIAG_OK",
    "JOB_NAME",
    "MVP_IMPLEMENTED_REQUIREMENT_IDS",
    "MVP_TIER2_SCOPED_REQUIREMENT_IDS",
    "ORG_CHART",
    "RequirementResult",
    "TABLES_DOC",
    "TIER1_ACTIVE_REQUIREMENT_IDS",
    "TIER_ACHIEVED_TO_CLASSIFICATION",
    "TIER_1_IDS",
    "TIERING_RULES_VERSION",
    "TableDescriptionQualityResult",
    "TierComputationResult",
    "_parse_dataset_fair_signals",
    "assess_column_description_quality",
    "assess_table_description_quality",
    "build_dataset_fqn_search_query",
    "build_dataset_urn",
    "build_fetch_dataset_structured_properties_query",
    "build_upsert_structured_property_mutation",
    "check_a1_2_01_access_request_documented",
    "check_a1_2_02_approver_ownership",
    "check_a1_2_03_interim_access_policy_via_contract",
    "check_f1_03_addressable_fqn",
    "check_f4_01_indexed_in_datahub",
    "check_i1_02_data_contract_present",
    "compute_a1_2_01_how_to_request_access_by_fqn",
    "compute_a1_2_02_approvers_by_fqn",
    "compute_f2_02_and_i1_01_for_fqn",
    "compute_f4_pass_and_reason_by_fqn",
    "compute_has_data_contract_by_fqn",
    "compute_i3_lineage_pass_and_totals_by_fqn",
    "compute_i3_ownership_pass_by_fqn",
    "compute_tier",
    "compute_tier_mvp",
    "cumulative_ids_for_tier",
    "tier_achieved_to_classification",
    "normalize_classification_to_sp_value",
    "dataset_id_for_platform",
    "dataset_name_from_urn",
    "evaluate_mvp_checks_from_row",
    "find_matching_dataset_urns",
    "fqn_matches",
    "list_platform_urns_for_fqn",
    "parse_search_result_urns",
    "push_classifications",
    "resolve_datahub_gms_base_url",
    "resolve_datahub_graphql_url",
    "resolve_datahub_urn_flags",
    "resolve_columns_metastore_snapshot",
    "structured_property_rows_from_fetch",
]
