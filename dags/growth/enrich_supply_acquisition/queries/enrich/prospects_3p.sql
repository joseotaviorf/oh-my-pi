WITH conversion_l2p AS (
    -- I bring all conversion events here to filter by prospects
    SELECT 
        ls.sk_supply_lead, 
        l3p.business_context,
        ls.id_lead,
        l3p.id_region,
        l3p.id_house,
        ls.id_lead AS id_lead_ebdb,
        -1 AS id_referred_by,
        'conversion_l2p' AS business_event,
        l3p.growth_status AS funnel_step,
        2 AS funnel_level,
        '3P' AS supply_source,
        CAST(NULL AS STRING) AS drop_step_reason,
        COALESCE(l3p.status, -1) AS aux_product_status,
        l3p.aux_hash,
        l3p.ts_event
    FROM datalake_supply_flows.leads_sks AS ls
    LEFT JOIN datalake_supply_flows.landing_3p AS l3p
        ON ls.id_lead = l3p.id_lead_3p
            AND l3p.growth_status = 'PROSPECT'
    WHERE ls.source = '3P' 
        AND l3p.aux_round_number = 1
        AND DATE(l3p.ts_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
drop_l2p AS (
    -- Here we are going to remove all leads that converted
    SELECT l.aux_hash
    FROM datalake_supply_flows.leads_3p AS l
    LEFT ANTI JOIN conversion_l2p
        USING (aux_hash) 
    GROUP BY ALL
),
discards_events AS (
    -- Here we are going to bring all the leads that were discarded based in hash
    SELECT *
    FROM datalake_supply_flows.landing_3p
    WHERE aux_round_number = 1
        AND aux_hash IN (SELECT * FROM drop_l2p)
        AND DATE(ts_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        AND growth_status = 'LEAD'
),
discards_l2p AS (
    SELECT 
        ls.sk_supply_lead, 
        l3p.business_context,
        ls.id_lead,
        l3p.id_region,
        l3p.id_house,
        ls.id_lead AS id_lead_ebdb,
        -1 AS id_referred_by,
        'drop_l2p' AS business_event,
        l3p.growth_status AS funnel_step,
        2 AS funnel_level,
        '3P' AS supply_source,
        l3p.reason AS drop_step_reason,
        COALESCE(l3p.status, -1) AS aux_product_status,
        l3p.aux_hash,
        l3p.ts_event
    FROM datalake_supply_flows.leads_sks AS ls
    JOIN discards_events AS l3p
        ON ls.id_lead = l3p.id_lead_3p
            AND (ls.source = '3P')
)

SELECT 
    sk_supply_lead,
    id_lead,
    id_lead_ebdb,
    id_house,
    id_region,
    supply_source,
    business_context,
    business_event,
    drop_step_reason,
    funnel_step,
    funnel_level,
    aux_product_status,
    aux_hash,
    ts_event,
    CURRENT_TIMESTAMP() AS ts_load
FROM discards_l2p
UNION ALL
SELECT 
    sk_supply_lead,
    id_lead,
    id_lead_ebdb,
    id_house,
    id_region,
    supply_source,
    business_context,
    business_event,
    drop_step_reason,
    funnel_step,
    funnel_level,
    aux_product_status,
    aux_hash,
    ts_event,
    CURRENT_TIMESTAMP() AS ts_load
FROM conversion_l2p