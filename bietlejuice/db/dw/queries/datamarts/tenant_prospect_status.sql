WITH
tps_contracts AS (
    SELECT DISTINCT
        flrf.sk_client,
        dr.city_group,
        dc.ts_signature,
        dc.sk_contract,
        'tenant prospect' AS contract_role,
        CAST(dt_annulment AS TIMESTAMP) AS ts_annulment,
        NULL::INT AS cs_order
    FROM
        dim_contract AS dc
        JOIN fact_listing_rent_flows AS flrf
            ON dc.sk_contract = flrf.sk_contract
        JOIN dim_region AS dr
            ON flrf.sk_region = dr.sk_region
),
contract_person AS (
    SELECT DISTINCT
        fcp.sk_user AS sk_client,
        dr.city_group,
        dc.ts_signature,
        dc.sk_contract,
        fcp.contract_role,
        CAST(dt_annulment AS TIMESTAMP) AS ts_annulment,
        ROW_NUMBER() OVER(PARTITION BY COALESCE(NULLIF(fcp.sk_user, -1), flrf.sk_client),
                                       dc.sk_contract,
                                       dr.city_group,
                                       dc.ts_signature
                          ORDER BY fcp.contract_role DESC) as cs_order
    FROM
        dim_contract AS dc
        JOIN fact_listing_rent_flows AS flrf
            ON dc.sk_contract = flrf.sk_contract
        JOIN dim_region AS dr
            ON flrf.sk_region = dr.sk_region
        JOIN quintoandar.fact_contract_people AS fcp
            ON dc.sk_contract = fcp.sk_contract
        FULL OUTER JOIN tps_contracts AS tc -- Anti Join with tps_contracts to get only aditional users
            ON tc.sk_client = fcp.sk_user
            AND tc.ts_signature = dc.ts_signature
    WHERE
        tc.sk_client IS NULL                -- Anti Join with tps_contracts to get only aditional users
        AND dc.ts_signature IS NOT NULL
        AND fcp.sk_user != -1
        AND fcp.contract_role IN ('tenant', 'dweller')
),
contract_flows AS (
    SELECT
        *
    FROM
        tps_contracts
    UNION
    SELECT
        *
    FROM
        contract_person
    WHERE
        cs_order = 1
),
events_base AS (
    -- Rent Flows
    SELECT DISTINCT
        rfi.sk_client,
        dr.city_group,
        rfi.ts_event,
        'rent_flow' AS event_type
    FROM
        datamarts.rent_flow_interactions as rfi
        JOIN dim_region AS dr
            USING(sk_region)
    WHERE
        rfi.rent_flow_order = 1
    GROUP BY 1,2,3,4

    UNION ALL

    -- Contracts signed
    SELECT DISTINCT
        sk_client,
        city_group,
        ts_signature AS ts_event,
        'contract signed as ' ||  contract_role AS event_type
    FROM
        contract_flows

    UNION ALL

    -- Contracts ended
    SELECT DISTINCT
        sk_client,
        city_group,
        ts_annulment AS ts_event,
        'contract ended' AS event_type
    FROM
        contract_flows
    WHERE
        ts_annulment IS NOT NULL
),
churn_dates AS (
    SELECT
        b.*,
        LAG(event_type) OVER(PARTITION BY sk_client, city_group ORDER BY ts_event) AS last_event,
        LAG(ts_event) OVER(PARTITION BY sk_client, city_group ORDER BY ts_event) AS ts_last_event,
        LEAD(ts_event) OVER(PARTITION BY sk_client, city_group ORDER BY ts_event ASC, event_type DESC) AS ts_next_event,
        CASE
            WHEN event_type LIKE 'contract signed%'
                THEN ts_event
            WHEN event_type = 'contract ended' AND last_event LIKE 'contract signed%'
                THEN ts_event
            WHEN event_type = 'contract ended' AND last_event = 'rent_flow'
                    AND DATEDIFF(DAY, ts_last_event, COALESCE(ts_next_event, CURRENT_DATE)) > 35
                THEN DATEADD(DAY, 35, ts_last_event)
            WHEN event_type NOT LIKE 'contract%'
                    AND DATEDIFF(DAY, ts_event, COALESCE(ts_next_event, CURRENT_DATE)) > 35
                THEN DATEADD(DAY, 35, ts_event)
        END AS ts_churn
    FROM
        events_base AS b
),
aux_churn_dates as (
    SELECT
        cd.*,
        FIRST_VALUE(ts_churn IGNORE NULLS) OVER(PARTITION BY sk_client, city_group ORDER BY ts_event ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS ts_next_churn
    FROM
        churn_dates AS cd
),
churned_periods AS (
    SELECT
        cd.sk_client,
        cd.city_group,
        cd.ts_churn AS ts_start,
        cd.ts_next_event AS ts_end,
        CASE
            WHEN cd.event_type LIKE 'contract signed%'
                THEN 'RENTED'
            ELSE 'CHURNED'
        END AS status,
        CASE
            WHEN cd.event_type = 'contract signed as tenant prospect'
                THEN 'Inactive by renting (tp)'
            WHEN cd.event_type = 'contract signed as tenant'
                THEN 'Inactive by renting (tenant)'
            WHEN cd.event_type = 'contract signed as dweller'
                THEN 'Inactive by renting (dweller)'
            WHEN cd.event_type = 'contract ended'
                THEN 'Contract ended'
            WHEN cd.event_type = 'rent_flow'
                THEN 'Inactivity'
        END AS status_detail,
        NULL::INT AS activation_order
    FROM
        aux_churn_dates AS cd
    WHERE
        ts_churn IS NOT NULL
),
active_periods AS (
    SELECT
        cd.sk_client,
        cd.city_group,
        MIN(cd.ts_event) AS ts_start,
        cd.ts_next_churn AS ts_end,
        'ACTIVE' AS status,
        NULL::TEXT AS status_detail,
        ROW_NUMBER() OVER(PARTITION BY cd.sk_client, cd.city_group ORDER BY ts_start) AS activation_order -- Get first activetion by client and city group
    FROM
        aux_churn_dates AS cd
    WHERE
        event_type = 'rent_flow'
    GROUP BY 1,2,4,5
),
base AS (
    SELECT
        *
    FROM
        churned_periods

    UNION ALL

    SELECT *
    FROM
        active_periods
)
SELECT
    sk_client,
    city_group,
    ts_start,
    ts_end,
    TO_CHAR(ts_start, 'YYYYMMDD') AS sk_start_date,
    TO_CHAR(ts_end, 'YYYYMMDD') AS sk_end_date,
    status,
    CASE
        WHEN activation_order = 1
            THEN 'First activation'
        WHEN LAG(status) OVER(PARTITION BY sk_client, city_group ORDER BY ts_start) = 'CHURNED'
            THEN COALESCE(status_detail, 'Recovered after churn')
        WHEN LAG(status) OVER(PARTITION BY sk_client, city_group ORDER BY ts_start) = 'RENTED'
            THEN COALESCE(status_detail, 'Recovered after renting')
        ELSE status_detail
    END AS status_detail,
	COALESCE(LEAD(status) OVER(PARTITION BY sk_client, city_group ORDER BY ts_start), 'STILL ACTIVE') AS next_status
FROM
    base