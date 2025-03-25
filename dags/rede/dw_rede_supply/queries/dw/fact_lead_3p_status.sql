SELECT
    id_status_change AS sk_status_event,
    lsk.sk_lead_3p * 100 + IF(lsc.business_context = 'SALE', 0, 1) AS sk_lead_3p_flow, -- For now, Sale will be version 0, and Rent will be version 1
    lsk.sk_lead_3p AS sk_lead_3p,
    COALESCE(dl3c.sk_lead_3p_context, -1) AS sk_lead_3p_context,
    COALESCE(fsk.sk_file, -1) AS sk_file,
    COALESCE(csk.sk_company, -1) AS sk_company,
    COALESCE(lsc.id_house, -1) AS sk_house,
    COALESCE(l3p.id_region, -1) AS sk_region,
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
    datalake_company.company_sks AS csk
    ON (lsc.id_company_hubspot IS NOT NULL AND csk.id_hubspot = lsc.id_company_hubspot)
LEFT JOIN
    datalake_rede_lead_acquisition.lead_3p_acquisition AS la
        ON la.id_lead_3p = lsc.id_lead_3p
        AND la.business_context = lsc.business_context
LEFT JOIN
    datalake_rede_lead_crawler.lead_3p_freshness AS lf
        ON lf.id_lead_3p = lsc.id_lead_3p
        AND lf.business_context = lsc.business_context
LEFT JOIN
    dw_rede.dim_lead_3p_context AS dl3c
        ON lsc.business_context = dl3c.business_context
        AND IF(lsc.business_context = 'SALE', l3p.sale_recurrency_type, l3p.rent_recurrency_type) = dl3c.recurrency_type
        AND IF(lsc.business_context = 'SALE', l3p.sale_integrator_trade_name, l3p.rent_integrator_trade_name) = dl3c.integrator_trade_name
        AND dl3c.acquisition_team = COALESCE(la.acquisition_team, 'N/A')
        AND dl3c.freshness = COALESCE(lf.freshness, 'N/A')