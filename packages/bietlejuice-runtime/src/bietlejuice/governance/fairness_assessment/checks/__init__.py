"""
FAIRness checks by pillar (F/A/I/R). Runtime evaluation: ``evaluate_mvp_checks_from_row``.

F2-02 / I1-01 heavy logic lives in ``schema_validation.compute_f2_02_and_i1_01_for_fqn`` (Spark driver);
thin check functions in ``checks/findable`` and ``checks/interoperable`` map row fields to
``RequirementResult``.
"""

from __future__ import annotations

from bietlejuice.governance.fairness_assessment.checks.accessible.a1_2_03_interim_access_via_contract import (  # noqa: E501
    check_a1_2_03_interim_access_policy_via_contract,
)
from bietlejuice.governance.fairness_assessment.checks.evaluation import (
    evaluate_mvp_checks_from_row,
)
from bietlejuice.governance.fairness_assessment.checks.findable.f1_01_persistent_identifier import (  # noqa: E501
    check_f1_01_persistent_id,
)
from bietlejuice.governance.fairness_assessment.checks.findable.f1_02_fqn_unique import (  # noqa: E501
    check_f1_02_fqn_unique,
)
from bietlejuice.governance.fairness_assessment.checks.findable.f1_03_addressable_fqn import (  # noqa: E501
    check_f1_03_addressable_fqn,
)
from bietlejuice.governance.fairness_assessment.checks.findable.f2_01_basic_rich_metadata import (  # noqa: E501
    check_f2_01_basic_rich_metadata,
)
from bietlejuice.governance.fairness_assessment.checks.findable.f2_02_substantive_column_descriptions import (  # noqa: E501
    check_f2_02_substantive_column_descriptions,
)
from bietlejuice.governance.fairness_assessment.checks.findable.f4_01_indexed_in_datahub import (  # noqa: E501
    check_f4_01_indexed_in_datahub,
)
from bietlejuice.governance.fairness_assessment.checks.interoperable.i1_01_documented_physical_fields import (  # noqa: E501
    check_i1_01_documented_physical_fields,
)
from bietlejuice.governance.fairness_assessment.checks.interoperable.i1_02_data_contract_present import (  # noqa: E501
    check_i1_02_data_contract_present,
)
from bietlejuice.governance.fairness_assessment.checks.interoperable.i3_01_ownership_in_catalog import (  # noqa: E501
    check_i3_01_ownership_in_catalog,
)
from bietlejuice.governance.fairness_assessment.checks.interoperable.i3_02_lineage_in_catalog import (  # noqa: E501
    check_i3_02_lineage_in_catalog,
)

__all__ = [
    "check_a1_2_03_interim_access_policy_via_contract",
    "check_f1_01_persistent_id",
    "check_f1_02_fqn_unique",
    "check_f1_03_addressable_fqn",
    "check_f2_01_basic_rich_metadata",
    "check_f2_02_substantive_column_descriptions",
    "check_f4_01_indexed_in_datahub",
    "check_i1_01_documented_physical_fields",
    "check_i1_02_data_contract_present",
    "check_i3_01_ownership_in_catalog",
    "check_i3_02_lineage_in_catalog",
    "evaluate_mvp_checks_from_row",
]
