WITH lead_acquisition AS (
    SELECT 
        ls.sk_supply_lead, 
        ls.id_lead,
        l3p.business_context,
        l3p.status,
        l3p.id_region,
        l3p.aux_hash,
        l3p.ts_event
    FROM datalake_supply_flows.leads_sks AS ls
    JOIN datalake_supply_flows.landing_3p AS l3p 
        ON ls.id_lead = l3p.id_lead_3p
            AND l3p.growth_status = 'LEAD'
    WHERE ls.source = '3P' 
        AND l3p.aux_round_number = 1
)

SELECT
    sk_supply_lead,
    id_lead,
    id_lead AS id_lead_ebdb,
    id_region,
    '3P' AS supply_source,
    business_context,
    'acquisition_tof2l' AS business_event,
    'LEAD' AS funnel_step,
    1 AS funnel_level,
    status AS aux_product_status,
    aux_hash,
    ts_event,
    CURRENT_TIMESTAMP() AS ts_load
FROM lead_acquisition
WHERE DATE(ts_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')