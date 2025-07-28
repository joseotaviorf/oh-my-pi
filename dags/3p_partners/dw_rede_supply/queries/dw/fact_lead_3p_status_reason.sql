WITH lead_3p_reason_changes AS (
    SELECT
        lsk.sk_lead_3p * 100 + IF(lrc.business_context = 'SALE', 0, 1) AS sk_lead_3p_flow, -- For now, Sale will be version 0, and Rent will be version 1
        lsk.sk_lead_3p,
        lrc.id_lead_3p,
        lr.sk_lead_3p_reason,
        COALESCE(l3p.id_region, -1) AS sk_region,
        COALESCE(BIGINT(DATE_FORMAT(lrc.ts_reason_started, 'yyyyMMdd')), -1) AS sk_reason_started_date,
        COALESCE(BIGINT(DATE_FORMAT(lrc.ts_reason_ended, 'yyyyMMdd')), -1) AS sk_reason_ended_date,
        lsrs.sk_lead_3p_status AS sk_status_when_reason_started,
        lrc.id_file,
        lrc.business_context,
        lrc.uuid_company,
        lrc.days_in_reason,
        lrc.status_when_reason_ended,
        lrc.growth_status_when_reason_ended,
        COALESCE(NULLIF(l3p.cnpj, 'Não informado'), 'Unknown') AS cnpj,
        IF(lrc.business_context = 'SALE', l3p.sale_recurrency_type, l3p.rent_recurrency_type) AS recurrency_type,
        IF(lrc.business_context = 'SALE', l3p.sale_integrator_trade_name, l3p.rent_integrator_trade_name) AS integrator_trade_name,
        COALESCE(la.acquisition_team, 'N/A') AS acquisition_team,
        COALESCE(lf.freshness, 'N/A') AS freshness,
        lrc.has_3p_access_control,
        lrc.is_waiting_for_enrichment_when_reason_ended,
        lrc.is_ineligible_when_reason_ended,
        lrc.is_discarded_when_reason_ended,
        lrc.is_requirement_met,
        lrc.ts_reason_started,
        lrc.ts_reason_ended,
        COALESCE(lrc.ts_reason_ended, lrc.ts_reason_started) AS ts_updated,
        YEAR(COALESCE(lrc.ts_reason_ended, lrc.ts_reason_started)) AS year,
        MONTH(COALESCE(lrc.ts_reason_ended, lrc.ts_reason_started)) AS month,
        DAY(COALESCE(lrc.ts_reason_ended, lrc.ts_reason_started)) AS day
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
        datalake_rede_lead_acquisition.lead_3p_acquisition AS la
            ON la.id_lead_3p = lrc.id_lead_3p
            AND la.business_context = lrc.business_context
    LEFT JOIN
        datalake_rede_lead_crawler.lead_3p_freshness AS lf
            ON lf.id_lead_3p = lrc.id_lead_3p
            AND lf.business_context = lrc.business_context
    WHERE
        DATE(COALESCE(lrc.ts_reason_ended, lrc.ts_reason_started)) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    lrc.sk_lead_3p_flow,
    lrc.sk_lead_3p,
    COALESCE(dl3c.sk_lead_3p_context, -1) AS sk_lead_3p_context,
    COALESCE(csk.sk_company, csk2.sk_company, -1) AS sk_company,
    COALESCE(fsk.sk_file, -1) AS sk_file,
    lrc.sk_lead_3p_reason,
    lrc.sk_region,
    lrc.sk_reason_started_date,
    lrc.sk_reason_ended_date,
    lrc.sk_status_when_reason_started,
    COALESCE(lsre.sk_lead_3p_status, -1) AS sk_status_when_reason_ended,
    lrc.days_in_reason,
    lrc.has_3p_access_control,
    lrc.is_requirement_met,
    lrc.ts_reason_started,
    lrc.ts_reason_ended,
    lrc.ts_updated,
    NOW() AS ts_load,
    lrc.year,
    lrc.month,
    lrc.day
FROM
    lead_3p_reason_changes AS lrc
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
        ON lrc.uuid_company IS NOT NULL 
        AND csk.uuid_company = lrc.uuid_company
LEFT JOIN
    datalake_company.company_sks AS csk2
        ON lrc.uuid_company IS NULL 
        AND csk2.extracted_3p_tag = lrc.cnpj
LEFT JOIN
    dw_rede.dim_lead_3p_context AS dl3c
        ON dl3c.business_context = lrc.business_context
        AND dl3c.recurrency_type = lrc.recurrency_type
        AND dl3c.integrator_trade_name = lrc.integrator_trade_name
        AND dl3c.acquisition_team = lrc.acquisition_team
        AND dl3c.freshness = lrc.freshness