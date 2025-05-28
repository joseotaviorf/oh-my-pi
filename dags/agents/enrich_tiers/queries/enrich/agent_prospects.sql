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
        DATE(pdr.ts_event) AS dt_event
    FROM
        datalake_demand_flows.prospect_daily_results AS pdr
    QUALIFY
        1 = ROW_NUMBER() OVER(PARTITION BY COALESCE(pdr.id_rent_flow, pdr.id_sale_flow), pdr.event_type, pdr.business_context ORDER BY pdr.ts_event ASC)
),
sale_visits AS (
    SELECT
        sv.id_booking,
        sv.id_agent,
        sv.ts_booking_created
    FROM
        datalake_sale_visit.sale_visit sv
    WHERE 
        sv.id_seller != sv.id_user_creation
    QUALIFY 
        1 = ROW_NUMBER() OVER(PARTITION BY sv.id_buyer ORDER BY sv.ts_booking_created)
)
SELECT
    sv.id_agent,
    aha.id_user,
    aha.id_user_negotiation_executive AS id_user_parent,
    pdr.id_prospect,
    pdr.business_context,
    pdr.event_name,
    sv.ts_booking_created AS ts_event,
    fb.year,
    fb.bimester
FROM
    sale_visits AS sv
JOIN
    filter_bimester AS fb
        ON DATE(sv.ts_booking_created) BETWEEN fb.bimester_start AND fb.bimester_end
LEFT JOIN
    prospect_daily_results AS pdr
        ON pdr.id_agent = sv.id_agent
        AND pdr.dt_event = DATE(sv.ts_booking_created)
        AND pdr.event_name in ("USER FIRST ACTIVATION", "USER RECOVERY", "USER RECOVERY IN OTHER CITY GROUP")
LEFT JOIN
    datalake_hub_services.agent_hub_alocation AS aha
        ON aha.id_agent = sv.id_agent
        AND aha.dt_reference = DATE(sv.ts_booking_created)
WHERE
    sv.id_agent IS NOT NULL