WITH
-----------------------------------------------------------
-- Query bookings, offers and talk to agent full history --
-----------------------------------------------------------
events AS (
    SELECT
        flrf.sk_client,
        db.id_property AS id_house,
        flrf.sk_region,
        db.dt_created AS ts_event
    FROM
        dim_booking AS db
        JOIN fact_listing_rent_Flows flrf
            USING(sk_booking)
    WHERE
        db.sk_booking > 0
        AND db.visit_intent = 'RENT'
        AND db.type = 'Visita'
        AND db.dt_created IS NOT NULL

    UNION ALL

    SELECT
        flrf.sk_client,
        o.id_property AS id_house,
        flrf.sk_region,
        o.dt_first_sent AS ts_event
    FROM
        dim_offer AS o
        JOIN fact_listing_rent_flows AS flrf
            USING(sk_offer)
    WHERE
        o.sk_offer > 0
        AND o.dt_first_sent IS NOT NULL

    UNION ALL

    SELECT
        tta.tenant_id::INT AS sk_client,
        tta.house_id::INT AS id_house,
        fhl.sk_region,
        tta.first_message_ts::timestamp AS ts_event
    FROM
        datamarts.talk_to_agent AS tta
        JOIN fact_house_listings AS fhl
            ON tta.sk_house_listing = fhl.sk_house_listing
    WHERE
        tta.business_context = 'RENT'
        AND tta.first_message_ts IS NOT NULL
),
----------------------------------------------------------------------------------------------------------------------
-- Merge activation events (offer, booking and talk to agent) and order them by user and rent_flows (user || house) --
----------------------------------------------------------------------------------------------------------------------
rent_flows_raw AS (
    SELECT
        evt.*,
        dr.city_group,
        evt.sk_client || '_' || evt.id_house AS sk_rf,
        ROW_NUMBER() OVER(PARTITION BY evt.sk_client, evt.id_house ORDER BY evt.ts_event) AS rent_flow_order
    FROM
        events AS evt
        JOIN dim_region AS dr
            ON evt.sk_region = dr.sk_region
),
contract_person AS (
    SELECT DISTINCT
        COALESCE(NULLIF(fcp.sk_user, -1), flrf.sk_client) AS sk_client,
        dr.city_group,
        dc.ts_signature,
        fcp.contract_role,
        CAST(dt_annulment AS TIMESTAMP) AS ts_annulment
    FROM
        dim_contract AS dc
        JOIN fact_listing_rent_flows AS flrf
            ON dc.sk_contract = flrf.sk_contract
        JOIN dim_region AS dr
            ON flrf.sk_region = dr.sk_region
        JOIN quintoandar.fact_contract_people AS fcp
            ON dc.sk_contract = fcp.sk_contract
    WHERE
        ts_signature IS NOT NULL
        AND fcp.contract_role IN ('tenant', 'dweller')
),
events_base AS (
    -- Rent Flows
    SELECT DISTINCT
        sk_client,
        city_group,
        ts_event,
        'rent_flow' AS event_type
    FROM
        rent_flows_raw
    WHERE
        rent_flow_order = 1
    GROUP BY 1,2,3,4

    UNION ALL

    -- Contracts signed
    SELECT DISTINCT
        sk_client,
        city_group,
        ts_signature AS ts_event,
        'contract signed as ' ||  contract_role AS event_type
    FROM
        contract_person

    UNION ALL

    -- Contracts ended
    SELECT DISTINCT
        sk_client,
        city_group,
        ts_annulment AS ts_event,
        'contract ended' AS event_type
    FROM
        contract_person
    WHERE
        ts_annulment IS NOT NULL
),
churn_dates AS (
    SELECT
        b.*,
        LAG(event_type) OVER(PARTITION BY sk_client, city_group ORDER BY ts_event) AS last_event,
        LEAD(ts_event) OVER(PARTITION BY sk_client, city_group ORDER BY ts_event ASC, event_type DESC) AS ts_next_event,
        CASE
            WHEN event_type LIKE 'contract signed%'
                THEN ts_event
            WHEN event_type = 'contract ended' AND last_event LIKE 'contract signed%'
                THEN ts_event
            WHEN event_type NOT LIKE 'contract%'
                    AND DATEDIFF(DAY, ts_event, COALESCE(ts_next_event, CURRENT_DATE)) >= 35
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
            WHEN cd.event_type = 'contract signed as tenant'
                THEN 'Inactive by renting (tenant)'
            WHEN cd.event_type = 'contract signed as dweller'
                THEN 'Inactive by renting (dweller)'
            WHEN cd.event_type = 'contract ended'
                THEN 'Contract ended'
            WHEN cd.event_type = 'rent_flow'
                THEN 'Inactivity'
        END AS status_detail
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
        NULL::TEXT AS status_detail
    FROM
        aux_churn_dates AS cd
    WHERE
        event_type = 'rent_flow'
    GROUP BY 1,2,4,5
),
base AS (
    SELECT *
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
        WHEN LAG(status) OVER(PARTITION BY sk_client, city_group ORDER BY ts_start) IS NULL AND status = 'ACTIVE'
            THEN 'First activation'
        WHEN LAG(status) OVER(PARTITION BY sk_client, city_group ORDER BY ts_start) = 'CHURNED'
            THEN COALESCE(status_detail, 'Recovered after churn')
        WHEN LAG(status) OVER(PARTITION BY sk_client, city_group ORDER BY ts_start) = 'RENTED'
            THEN COALESCE(status_detail, 'Recovered after renting')
        ELSE status_detail
    END AS status_detail
FROM
    base