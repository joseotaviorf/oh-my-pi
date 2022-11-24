SELECT
    lsk.sk_lead_3p,
    COALESCE(csk.sk_company, -1) AS sk_company,
    COALESCE(fsk.sk_file, -1) AS sk_file,
    lr.sk_lead_3p_reason,
    COALESCE(BIGINT(DATE_FORMAT(lrc.ts_reason_started, 'yyyyMMdd')), -1) AS sk_reason_started_date,
    COALESCE(BIGINT(DATE_FORMAT(lrc.ts_reason_ended, 'yyyyMMdd')), -1) AS sk_reason_ended_date,
    lsrs.sk_lead_3p_status AS sk_status_when_reason_started,
    COALESCE(lsre.sk_lead_3p_status, -1) AS sk_status_when_reason_ended,
    lrc.days_in_reason,
    lrc.is_requirement_met,
    lrc.ts_reason_started,
    lrc.ts_reason_ended,
    NOW() AS ts_load
FROM
    datalake_rede_supply.lead_3p_reason_changes AS lrc
JOIN
    datalake_brokers_supply_processor.lead_3p AS l3p
        ON lrc.id_lead_3p = l3p.id
JOIN
    datalake_rede_supply.lead_3p_sks AS lsk
        ON lsk.id_lead_3p = lrc.id_lead_3p
JOIN
    datalake_rede_supply.lead_3p_reasons AS lr
        ON lr.reason = lrc.reason
JOIN
    datalake_rede_supply.lead_3p_status AS lsrs
        ON lsrs.status = lrc.status_when_reason_started
        AND lsrs.growth_status = lrc.growth_status_when_reason_started
        AND lsrs.is_waiting_for_enrichment = lrc.is_waiting_for_enrichment_when_reason_started
        AND lsrs.is_ineligible = lrc.is_ineligible_when_reason_started
        AND lsrs.is_discarded = lrc.is_discarded_when_reason_started
LEFT JOIN
    datalake_rede_supply.lead_3p_status AS lsre
        ON lsre.status = lrc.status_when_reason_ended
        AND lsre.growth_status = lrc.growth_status_when_reason_ended
        AND lsre.is_waiting_for_enrichment = lrc.is_waiting_for_enrichment_when_reason_ended
        AND lsre.is_ineligible = lrc.is_ineligible_when_reason_ended
        AND lsre.is_discarded = lrc.is_discarded_when_reason_ended
LEFT JOIN
    datalake_rede_supply.file_sks AS fsk
        ON fsk.id_file = lrc.id_file
LEFT JOIN
    datalake_rede_company.company_sks AS csk
    ON (lrc.id_company_hubspot IS NOT NULL AND csk.id_hubspot = lrc.id_company_hubspot)
    OR (lrc.id_company_hubspot IS NULL AND csk.extracted_3p_tag = COALESCE(NULLIF(l3p.cnpj, 'Não informado'), 'Unknown'))
