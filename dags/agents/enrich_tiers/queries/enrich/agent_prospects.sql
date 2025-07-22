WITH filter_bimester AS (
    SELECT DISTINCT
        ad.bimester_start,
        ad.bimester_end,
        ad.bimester,
        ad.year
    FROM 
        datalake_quintoandar.aux_date AS ad
    WHERE
        ad.date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
prospect_daily_results AS (
    SELECT
        pdr.id_prospect,
        pdr.id_booking,
        pdr.id_agent,
        pdr.event_name,
        pdr.business_context,
        pdr.referral_type,
        DATE(pdr.ts_event) AS dt_event
    FROM
        datalake_demand_flows.prospect_daily_results AS pdr
    QUALIFY
        1 = ROW_NUMBER() OVER(PARTITION BY COALESCE(pdr.id_rent_flow, pdr.id_sale_flow), pdr.event_type, pdr.business_context ORDER BY pdr.ts_event ASC)
)
SELECT
    pdr.id_agent,
    aha.id_user,
    aha.id_user_negotiation_executive AS id_user_parent,
    pdr.id_prospect,
    pdr.business_context,
    pdr.event_name,
    pdr.dt_event,
    fb.year,
    fb.bimester
FROM
    prospect_daily_results AS pdr
JOIN
    filter_bimester AS fb
        ON pdr.dt_event BETWEEN fb.bimester_start AND fb.bimester_end
LEFT JOIN
    datalake_hub_services.agent_hub_alocation AS aha
        ON aha.id_agent = pdr.id_agent
        AND aha.dt_reference = pdr.dt_event
WHERE
    pdr.id_agent IS NOT NULL
    AND pdr.event_name in ("USER FIRST ACTIVATION", "USER RECOVERY", "USER RECOVERY IN OTHER CITY GROUP")
    AND pdr.referral_type <> 'Rede'