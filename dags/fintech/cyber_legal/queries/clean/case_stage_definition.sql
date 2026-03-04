SELECT
    CDTYPE AS id_case_type,
    CDSTGID AS id_stage,
    CDDESC AS stage_description,
    CDORDER AS stage_order,
    CDSUBTYPE AS stage_subtype_description,
    CDPREDYS AS max_previous_system_days,
    CDDAYS AS required_days_for_stage,
    CDRESPDAYS AS litigator_attorney_days,
    CDSUPVDAYS AS supervisor_attorney_days,
    CDAMT AS authorized_expense_amount,
    CDPOSDYS AS max_post_system_days,
    CDAMTUNIT AS unit_amount,
    NOW() AS ts_load
FROM datalake_cyber_legal_raw.castadf
