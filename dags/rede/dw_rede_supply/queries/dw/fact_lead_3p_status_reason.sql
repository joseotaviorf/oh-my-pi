WITH max_sk AS (
    SELECT
        MAX(sk_reason_event) AS max_sk_reason_event
    FROM
        dw_rede.fact_lead_3p_status_reason
)
SELECT
    COALESCE(flsr.sk_reason_event, max_sk_reason_event + MONOTONICALLY_INCREASING_ID() + 1) AS sk_reason_event,
    lsk.sk_lead_3p * 100 + IF(lrc.business_context = 'SALE', 0, 1) AS sk_lead_3p_flow, -- For now, Sale will be version 0, and Rent will be version 1
    lsk.sk_lead_3p,
    COALESCE(dl3c.sk_lead_3p_context, -1) AS sk_lead_3p_context,
    COALESCE(csk.sk_company, -1) AS sk_company,
    COALESCE(fsk.sk_file, -1) AS sk_file,
    lr.sk_lead_3p_reason,
    COALESCE(l3p.id_region, -1) AS sk_region,
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
    datalake_rede_supply.lead_3p_reason_changes AS lrc,
    max_sk
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
    datalake_company.company_sks AS csk
    ON (lrc.uuid_company IS NOT NULL AND csk.uuid_company = lrc.uuid_company)
    OR (lsc.id_company_hubspot IS NULL AND csk.extracted_3p_tag = COALESCE(NULLIF(l3p.cnpj, 'Não informado'), 'Unknown'))
LEFT JOIN
    datalake_rede_lead_acquisition.lead_3p_acquisition AS la
        ON la.id_lead_3p = lrc.id_lead_3p
        AND la.business_context = lrc.business_context
LEFT JOIN
    datalake_rede_lead_crawler.lead_3p_freshness AS lf
        ON lf.id_lead_3p = lrc.id_lead_3p
        AND lf.business_context = lrc.business_context
LEFT JOIN
    dw_rede.dim_lead_3p_context AS dl3c
        ON lrc.business_context = dl3c.business_context
        AND IF(lrc.business_context = 'SALE', l3p.sale_recurrency_type, l3p.rent_recurrency_type) = dl3c.recurrency_type
        AND IF(lrc.business_context = 'SALE', l3p.sale_integrator_trade_name, l3p.rent_integrator_trade_name) = dl3c.integrator_trade_name
        AND dl3c.acquisition_team = COALESCE(la.acquisition_team, 'N/A')
        AND dl3c.freshness = COALESCE(lf.freshness, 'N/A')

LEFT JOIN
    dw_rede.fact_lead_3p_status_reason AS flsr
        ON flsr.sk_lead_3p_flow = lsk.sk_lead_3p * 100 + IF(lrc.business_context = 'SALE', 0, 1)
        AND flsr.sk_lead_3p_reason = lr.sk_lead_3p_reason
        AND flsr.ts_reason_started = lrc.ts_reason_started