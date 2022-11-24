WITH funnel AS (
    SELECT
        id_lead_3p,
        LEAST(ts_lead, ts_prospect, ts_qualified, ts_opportunity, ts_first_listing) AS ts_lead,
        LEAST(ts_prospect, ts_qualified, ts_opportunity, ts_first_listing) AS ts_prospect,
        LEAST(ts_qualified, ts_opportunity, ts_first_listing) AS ts_qualified,
        LEAST(ts_opportunity, ts_first_listing) AS ts_opportunity,
        ts_first_listing
    FROM (
        SELECT
            id_lead_3p,
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
)
SELECT
    lsk.sk_lead_3p,
    COALESCE(fsk.sk_file, -1) AS sk_file,
    COALESCE(csk.sk_company, -1) AS sk_company,
    ls.sk_lead_3p_status,
    COALESCE(h.id, -1) AS sk_house,
    COALESCE(BIGINT(DATE_FORMAT(f.ts_lead, 'yyyyMMdd')), -1) AS sk_lead_date,
    COALESCE(BIGINT(DATE_FORMAT(f.ts_prospect, 'yyyyMMdd')), -1) AS sk_prospect_date,
    COALESCE(BIGINT(DATE_FORMAT(f.ts_qualified, 'yyyyMMdd')), -1) AS sk_qualified_date,
    COALESCE(BIGINT(DATE_FORMAT(f.ts_opportunity, 'yyyyMMdd')), -1) AS sk_opportunity_date,
    COALESCE(BIGINT(DATE_FORMAT(f.ts_first_listing, 'yyyyMMdd')), -1) AS sk_first_listing_date,
    DATEDIFF(f.ts_prospect, f.ts_lead) AS days_lead_to_prospect,
    DATEDIFF(f.ts_qualified, f.ts_lead) AS days_lead_to_qualified,
    DATEDIFF(f.ts_opportunity, f.ts_lead) AS days_lead_to_opportunity,
    DATEDIFF(f.ts_first_listing, f.ts_lead) AS days_lead_to_first_listing,
    f.ts_lead,
    f.ts_prospect,
    f.ts_qualified,
    f.ts_opportunity,
    f.ts_first_listing,
    NOW() AS ts_load
FROM
    funnel AS f
JOIN
    datalake_brokers_supply_processor.lead_3p AS l3p
        ON f.id_lead_3p = l3p.id
LEFT JOIN
    datalake_ebdb_clean.house AS h
        ON h.id_external = l3p.uuid_lead
JOIN
    datalake_rede_supply.lead_3p_status_changes AS lsc
        ON f.id_lead_3p = lsc.id_lead_3p
        AND lsc.ts_status_ended IS NULL
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