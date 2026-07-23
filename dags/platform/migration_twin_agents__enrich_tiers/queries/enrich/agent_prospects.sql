WITH prospect_daily_results AS (
    SELECT
        pdr.id_prospect,
        pdr.id_booking,
        pdr.id_agent,
        pdr.event_name,
        pdr.business_context,
        pdr.referral_type,
        pdr.ts_event,
        DATE(pdr.ts_event) AS dt_event,
        pdr.year,
        pdr.month,
        pdr.day
    FROM
        datalake_demand_flows.prospect_daily_results AS pdr
    QUALIFY
        1 = ROW_NUMBER() OVER(PARTITION BY COALESCE(pdr.id_rent_flow, pdr.id_sale_flow), pdr.event_type, pdr.business_context ORDER BY pdr.ts_event ASC)
)
SELECT
    pdr.id_agent,
    u.id AS id_user,
    u.uuid_person,
    pdr.id_prospect,
    UPPER(pdr.business_context) AS business_context,
    pdr.event_name,
    pdr.ts_event,
    pdr.year,
    pdr.month,
    pdr.day
FROM
    prospect_daily_results AS pdr
JOIN
    datalake_ebdb_user.user AS u
        ON u.id_agent = pdr.id_agent
WHERE
    MAKE_DATE(pdr.year, pdr.month, pdr.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND pdr.id_agent IS NOT NULL
    AND pdr.event_name in ("USER FIRST ACTIVATION", "USER RECOVERY", "USER RECOVERY IN OTHER CITY GROUP")
    AND pdr.referral_type <> 'Rede'