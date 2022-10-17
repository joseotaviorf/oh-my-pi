SELECT
    sk_lead_3p_status,
    status,
    growth_status,
    CASE
        WHEN is_waiting_for_enrichment THEN 'WAITING FOR ENRICHMENT'
        ELSE 'NOT WAITING FOR ENRICHMENT'
    END AS waiting_for_enrichment_indicator,
    CASE
        WHEN is_ineligible THEN 'INELIGIBLE'
        ELSE 'ELIGIBLE'
    END AS ineligible_indicator,
    CASE
        WHEN is_discarded THEN 'DISCARDED'
        ELSE 'NOT DISCARDED'
    END AS discarded_indicator,
    is_waiting_for_enrichment,
    is_ineligible,
    is_discarded,
    NOW() AS ts_load
FROM
    datalake_rede_supply.lead_3p_status
