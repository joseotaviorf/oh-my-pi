WITH
dim_house AS (
    SELECT
        id AS sk_house,
        id_region AS sk_region
    FROM
        datalake_ebdb_clean_prod.house
    GROUP BY 1,2
),
events AS (
    SELECT
        fsf.sk_sale_flow,
        fsf.sk_buyer,
        fsf.sk_region,
        db.dt_created AS ts_event
    FROM
        dim_booking AS db
        JOIN sale.fact_visits AS fv
            USING(sk_booking)
        JOIN sale.fact_sale_flows AS fsf
            ON fsf.sk_sale_flow = fv.sk_sale_flow
    WHERE
        db.sk_booking > 0
        AND db.visit_intent = 'SALE'
        AND db.type = 'Visita'
    UNION ALL
    SELECT
        fsf.sk_sale_flow,
        fsf.sk_buyer,
        fsf.sk_region,
        o.ts_offer_submitted AS ts_event
    FROM
        sale.dim_offer AS o
        JOIN sale.fact_offers AS fo
            USING(sk_offer)
        JOIN sale.fact_sale_flows AS fsf
            ON fsf.sk_sale_flow = fo.sk_sale_flow
    UNION ALL
    SELECT
        tenant_id || '_' || house_id AS sk_sale_flow,
        tenant_id::INT AS sk_buyer,
        dh.sk_region,
        a.first_message_ts::timestamp AS ts_event
    FROM
        datamarts.talk_to_agent AS a
        JOIN dim_house AS dh
            ON a.house_id = dh.sk_house
        JOIN sale.fact_sale_flows AS fsf
            ON fsf.sk_sale_flow = a.tenant_id || '_' || a.house_id
    WHERE
        a.business_context = 'SALE'
        AND a.first_message_ts IS NOT NULL
),
---------------------------------------------------------
-- Order events by user and sale_flows (user || house) --
---------------------------------------------------------
sale_flows AS (
    SELECT
        evt.ts_event,
        dr.city_group,
        evt.sk_sale_flow,
        evt.sk_buyer,
        ROW_NUMBER() OVER(PARTITION BY evt.sk_sale_flow
                            ORDER BY evt.ts_event) AS sale_flow_order
    FROM
        events AS evt
        JOIN dim_region AS dr
            USING(sk_region)
),
events_base AS (
    SELECT DISTINCT
        sk_buyer,
        city_group,
        ts_event,
        'sale_flow' AS event_type
    FROM
        sale_flows
    WHERE
        sale_flow_order = 1
        
    UNION ALL
    
    SELECT
        fo.sk_buyer,
        dr.city_group,
        dsa.ts_sale_agreement_signed AS ts_event,
        'ccv_signed' AS event_type
    FROM sale.fact_offers AS fo
        JOIN sale.dim_sale_agreement AS dsa
            ON fo.sk_offer = dsa.sk_offer
        JOIN dim_region AS dr
            USING(sk_region)
    WHERE
        sk_sale_agreement_signed_date > 0
),
churn_dates AS (
    SELECT
        b.*,
        LAG(event_type) OVER(PARTITION BY sk_buyer, city_group ORDER BY ts_event) AS last_event,
        LAG(ts_event) OVER(PARTITION BY sk_buyer, city_group ORDER BY ts_event) AS ts_last_event,
        LEAD(ts_event) OVER(PARTITION BY sk_buyer, city_group ORDER BY ts_event ASC, event_type DESC) AS ts_next_event,
        CASE
            WHEN event_type = 'ccv_signed'
                THEN ts_event
            WHEN DATEDIFF(DAY, ts_event, COALESCE(ts_next_event, CURRENT_DATE)) > 90
                THEN DATEADD(DAY, 90, ts_event)
            ELSE NULL
        END AS ts_churn
    FROM
        events_base AS b
),
aux_churn_dates as (
    SELECT
        cd.*,
        FIRST_VALUE(ts_churn IGNORE NULLS) OVER(PARTITION BY sk_buyer, city_group ORDER BY ts_event ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS ts_next_churn
    FROM
        churn_dates AS cd
),
churned_periods AS (
    SELECT
        cd.sk_buyer,
        cd.city_group,
        cd.ts_churn AS ts_start,
        cd.ts_next_event AS ts_end,
        CASE
            WHEN cd.event_type = 'ccv_signed'
                THEN 'SIGNED CCV'
            ELSE 'CHURNED'
        END AS status,
        NULL::TIMESTAMP AS ts_nbp,
        NULL::INT AS activation_order
    FROM
        aux_churn_dates AS cd
    WHERE
        ts_churn IS NOT NULL
),
active_periods AS (
    SELECT
        cd.sk_buyer,
        cd.city_group,
        MIN(cd.ts_event) AS ts_start,
        cd.ts_next_churn AS ts_end,
        'ACTIVE' AS status,
        MIN(ts_start) OVER(PARTITION BY cd.sk_buyer) AS ts_nbp, -- Get first activetion by client,
        ROW_NUMBER() OVER(PARTITION BY cd.sk_buyer, cd.city_group ORDER BY ts_start) AS activation_order -- Get first activetion by client and city group
    FROM
        aux_churn_dates AS cd
    WHERE
        event_type = 'sale_flow'
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
    sk_buyer,
    city_group,
    ts_start,
    ts_end,
    TO_CHAR(ts_start, 'YYYYMMDD')::INT AS sk_start_date,
    TO_CHAR(ts_end, 'YYYYMMDD')::INT AS sk_end_date,
    status,
    CASE
        WHEN activation_order = 1 AND ts_start = ts_nbp
            THEN 'New BP'
        WHEN activation_order = 1
            THEN 'First activation in city_group'
        WHEN status = 'SIGNED CCV'
            THEN 'Inactive by signing CCV'
        WHEN status = 'CHURNED'
            THEN 'Inactivity'
        WHEN LAG(status) OVER(PARTITION BY sk_buyer, city_group ORDER BY ts_start) = 'CHURNED'
            THEN 'Recovered after churn'
        WHEN LAG(status) OVER(PARTITION BY sk_buyer, city_group ORDER BY ts_start) = 'SIGNED CCV'
            THEN 'Recovered after ccv signed'
        ELSE NULL
    END AS status_detail,
    MIN(ts_nbp) OVER(PARTITION BY sk_buyer) AS ts_first_activation,
    FIRST_VALUE(CASE WHEN ts_start = ts_nbp THEN city_group END) OVER(PARTITION BY sk_buyer ORDER BY ts_start ROWS UNBOUNDED PRECEDING) AS city_group_first_activation
FROM
    base