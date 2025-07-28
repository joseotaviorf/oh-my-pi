SELECT
    sk_lead_3p_reason,
    reason,
    reason_type,
    has_3p_access_control,
    is_ineligible_reason,
    is_discard_reason,
    is_enrichment_reason,
    NOW() AS ts_load
FROM
    datalake_rede_supply.lead_3p_reasons