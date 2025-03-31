WITH funnel AS (
    SELECT
        id_lead_3p,
        business_context,
        LEAST(ts_lead, ts_prospect, ts_qualified, ts_opportunity, ts_first_listing) AS ts_lead,
        LEAST(ts_prospect, ts_qualified, ts_opportunity, ts_first_listing) AS ts_prospect,
        LEAST(ts_qualified, ts_opportunity, ts_first_listing) AS ts_qualified,
        LEAST(ts_opportunity, ts_first_listing) AS ts_opportunity,
        ts_first_listing
    FROM (
        SELECT
            id_lead_3p,
            business_context,
            growth_status,
            ts_status_started
        FROM
            datalake_rede_supply.lead_3p_status_changes
    )
    PIVOT (
        MIN(ts_status_started)
        FOR (growth_status) IN (
            'LEAD' AS ts_lead,
            'PROSPECT' AS ts_prospect,
            'QUALIFIED' AS ts_qualified,
            'OPPORTUNITY' AS ts_opportunity,
            'FIRST_LISTING' AS ts_first_listing
        )
    )
),
updates AS (
    SELECT
        id_house,
        COUNT_IF(event_type = 'HOUSE_UPDATED') AS total_house_updates
    FROM
        datalake_rede_supply.listing_revisions
    GROUP BY 1
),
first_registered AS (
    SELECT
        id_lead_3p,
        business_context,
        MIN(CASE WHEN status = 'REGISTERED' THEN ts_status_started END) AS ts_registered,
        MIN(CASE WHEN status = 'UNPUBLISHED' THEN ts_status_started END) AS ts_first_unpublished
    FROM
        datalake_rede_supply.lead_3p_status_changes
    GROUP BY 1, 2
),
lead_house AS (
    SELECT
        id AS id_house,
        id_external
    FROM
        datalake_ebdb_clean.house
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_external ORDER BY dt_creation) = 1 
)
SELECT
    lsk.sk_lead_3p * 100 + IF(f.business_context = 'SALE', 0, 1) AS sk_lead_3p_flow, -- For now, Sale will be version 0, and Rent will be version 1
    lsk.sk_lead_3p,
    COALESCE(dl3c.sk_lead_3p_context, -1) AS sk_lead_3p_context,
    COALESCE(fsk.sk_file, -1) AS sk_file,
    COALESCE(csk.sk_company, -1) AS sk_company,
    ls.sk_lead_3p_status,
    COALESCE(lsc.id_house, lh.id_house, -1) AS sk_house,
    COALESCE(l3p.id_region, -1) AS sk_region,
    COALESCE(BIGINT(DATE_FORMAT(lf.dt_supply_processor, 'yyyyMMdd')), -1) AS sk_first_version_sent_date,
    COALESCE(BIGINT(DATE_FORMAT(lf.dt_crawler, 'yyyyMMdd')), -1) AS sk_crawler_date,
    COALESCE(BIGINT(DATE_FORMAT(f.ts_lead, 'yyyyMMdd')), -1) AS sk_lead_date,
    COALESCE(BIGINT(DATE_FORMAT(f.ts_prospect, 'yyyyMMdd')), -1) AS sk_prospect_date,
    COALESCE(BIGINT(DATE_FORMAT(f.ts_qualified, 'yyyyMMdd')), -1) AS sk_qualified_date,
    COALESCE(BIGINT(DATE_FORMAT(f.ts_opportunity, 'yyyyMMdd')), -1) AS sk_opportunity_date,
    COALESCE(BIGINT(DATE_FORMAT(fr.ts_registered, 'yyyyMMdd')), -1) AS sk_registered_date,
    COALESCE(BIGINT(DATE_FORMAT(f.ts_first_listing, 'yyyyMMdd')), -1) AS sk_first_listing_date,
    COALESCE(BIGINT(DATE_FORMAT(fr.ts_first_unpublished, 'yyyyMMdd')), -1) AS sk_first_unpublished_date,
    total_house_updates,
    lf.days_crawler_to_supply_processor AS days_crawler_to_first_version_sent,
    DATEDIFF(f.ts_prospect, f.ts_lead) AS days_lead_to_prospect,
    DATEDIFF(f.ts_qualified, f.ts_lead) AS days_lead_to_qualified,
    DATEDIFF(f.ts_opportunity, f.ts_lead) AS days_lead_to_opportunity,
    DATEDIFF(f.ts_first_listing, f.ts_lead) AS days_lead_to_first_listing,
    lf.dt_supply_processor AS dt_first_version_sent,
    lf.dt_crawler,
    f.ts_lead,
    f.ts_prospect,
    f.ts_qualified,
    f.ts_opportunity,
    fr.ts_registered,
    f.ts_first_listing,
    fr.ts_first_unpublished,
    NOW() AS ts_load
FROM
    datalake_rede_supply.lead_3p_sks AS lsk
LEFT JOIN
    funnel AS f
        ON f.id_lead_3p = lsk.id_lead_3p
LEFT JOIN
    first_registered AS fr
        ON f.id_lead_3p = fr.id_lead_3p
        AND f.business_context = fr.business_context
LEFT JOIN
    datalake_brokers_supply_processor.lead_3p AS l3p
        ON f.id_lead_3p = l3p.id
LEFT JOIN
    datalake_rede_supply.lead_3p_status_changes AS lsc
        ON f.id_lead_3p = lsc.id_lead_3p
        AND f.business_context = lsc.business_context
        AND lsc.ts_status_ended IS NULL
LEFT JOIN
    lead_house AS lh
        ON lh.id_external = l3p.uuid_lead
LEFT JOIN
    updates AS u
        ON COALESCE(lsc.id_house, lh.id_house) = u.id_house
LEFT JOIN
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
        ON (lsc.uuid_company IS NOT NULL AND csk.uuid_company = lsc.uuid_company)
        OR (lsc.uuid_company IS NULL AND csk.extracted_3p_tag = COALESCE(NULLIF(l3p.cnpj, 'Não informado'), 'Unknown'))
LEFT JOIN
    datalake_rede_lead_acquisition.lead_3p_acquisition AS la
        ON la.id_lead_3p = l3p.id
        AND la.business_context = f.business_context
LEFT JOIN
    datalake_rede_lead_crawler.lead_3p_freshness AS lf
        ON lf.id_lead_3p = l3p.id
        AND lf.business_context = f.business_context
LEFT JOIN
    dw_rede.dim_lead_3p_context AS dl3c
        ON f.business_context = dl3c.business_context
        AND IF(f.business_context = 'SALE', l3p.sale_recurrency_type, l3p.rent_recurrency_type) = dl3c.recurrency_type
        AND IF(f.business_context = 'SALE', l3p.sale_integrator_trade_name, l3p.rent_integrator_trade_name) = dl3c.integrator_trade_name
        AND dl3c.acquisition_team = COALESCE(la.acquisition_team, 'N/A')
        AND dl3c.freshness = COALESCE(lf.freshness, 'N/A')