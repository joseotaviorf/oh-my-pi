SELECT
    id_status_change AS sk_status_event,
    lsk.sk_lead_3p AS sk_lead_3p,
    COALESCE(fsk.sk_file, -1) AS sk_file,
    COALESCE(csk.sk_company, -1) AS sk_company,
    COALESCE(lsc.id_house, -1) AS sk_house,
    ls.sk_lead_3p_status AS sk_lead_3p_status,
    COALESCE(BIGINT(DATE_FORMAT(lsc.ts_status_started, 'yyyyMMdd')), -1) AS sk_status_started_date,
    COALESCE(BIGINT(DATE_FORMAT(lsc.ts_status_ended, 'yyyyMMdd')), -1) AS sk_status_ended_date,
    days_in_status,
    ts_status_started,
    ts_status_ended,
    NOW() AS ts_load
FROM
    datalake_rede_supply.lead_3p_status_changes AS lsc
JOIN
    datalake_brokers_supply_processor.lead_3p AS l3p
        ON lsc.id_lead_3p = l3p.id
JOIN
    datalake_rede_supply.lead_3p_sks AS lsk
        ON lsk.id_lead_3p = lsc.id_lead_3p
JOIN
    datalake_rede_supply.lead_3p_status AS ls
        ON lsc.status = ls.status
        AND lsc.growth_status = ls.growth_status
        AND lsc.is_waiting_for_enrichment = ls.is_waiting_for_enrichment
        AND lsc.is_ineligible = ls.is_ineligible
        AND lsc.is_discarded = ls.is_discarded
LEFT JOIN
    datalake_rede_supply.file_sks AS fsk
        ON fsk.id_file = lsc.id_file
LEFT JOIN
    datalake_rede_company.company_sks AS csk
    ON (lsc.id_company_hubspot IS NOT NULL AND csk.id_hubspot = lsc.id_company_hubspot)
    OR (lsc.id_company_hubspot IS NULL AND csk.extracted_3p_tag = COALESCE(NULLIF(l3p.cnpj, 'Não informado'), 'Unknown'))