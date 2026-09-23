WITH matches AS (
    SELECT
        fee_1.sk_sale_demand_event,
        fee_1.sk_event_date,
        fee_1.sk_event_type,
        fee_1.sk_booking,
        fee_1.sk_offer,
        fee_1.sk_house,
        fee_1.sk_region,
        fee_1.sk_buyer,
        fee_1.sk_seller,
        fee_1.sk_agent,
        fee_1.sk_agent_work_contract,
        fee_1.sk_business_unit,
        fee_1.sk_broker_supply,
        fee_1.sk_broker_demand,
        fee_1.sk_secretariat_booking_creator,
        fee_1.sk_secretariat_on_event,
        fee_1.sk_last_secretariat,
        fee_1.year,
        fee_1.month,
        fee_1.day,
        fee_1.ts_event AS ts_base_event,
        fee_2.sk_event_type AS conversion_sk_event_type,
        fee_2.sk_event_date AS conversion_sk_event_date,
        fee_2.ts_event AS conversion_ts_event
    FROM
        dw_sale.fact_sale_demand_event AS fee_1
    JOIN
        dw_sale.fact_sale_demand_event AS fee_2
            ON fee_1.sk_booking = fee_2.sk_booking -- If the first event is booking related, we use booking as key
    WHERE
        CAST(fee_1.sk_offer AS STRING) = '-1'
        AND fee_1.sk_event_type != fee_2.sk_event_type

    UNION ALL

    SELECT
        fee_1.sk_sale_demand_event,
        fee_1.sk_event_date,
        fee_1.sk_event_type,
        fee_1.sk_booking,
        fee_1.sk_offer,
        fee_1.sk_house,
        fee_1.sk_region,
        fee_1.sk_buyer,
        fee_1.sk_seller,
        fee_1.sk_agent,
        fee_1.sk_agent_work_contract,
        fee_1.sk_business_unit,
        fee_1.sk_broker_supply,
        fee_1.sk_broker_demand,
        fee_1.sk_secretariat_booking_creator,
        fee_1.sk_secretariat_on_event,
        fee_1.sk_last_secretariat,
        fee_1.year,
        fee_1.month,
        fee_1.day,
        fee_1.ts_event AS ts_base_event,
        fee_2.sk_event_type AS conversion_sk_event_type,
        fee_2.sk_event_date AS conversion_sk_event_date,
        fee_2.ts_event AS conversion_ts_event
    FROM
        dw_sale.fact_sale_demand_event AS fee_1
    JOIN
        dw_sale.fact_sale_demand_event AS fee_2
            ON fee_1.sk_offer = fee_2.sk_offer -- Otherwise, use offer as key
    WHERE
        CAST(fee_1.sk_offer AS STRING) != '-1'
        AND fee_1.sk_event_type != fee_2.sk_event_type
    -- fee_1.sk_offer = '-1' and fee_1.sk_offer != '-1' partition fee_1 into disjoint sets,
    -- so UNION ALL cannot double-count a fee_1 row the way it would for a true OR-across-columns join.
),
joined AS (
    SELECT
        m.sk_sale_demand_event,
        m.sk_event_date,
        m.sk_event_type,
        m.sk_booking,
        m.sk_offer,
        m.sk_house,
        m.sk_region,
        m.sk_buyer,
        m.sk_seller,
        m.sk_agent,
        m.sk_agent_work_contract,
        m.sk_business_unit,
        m.sk_broker_supply,
        m.sk_broker_demand,
        m.sk_secretariat_booking_creator,
        m.sk_secretariat_on_event,
        m.sk_last_secretariat,
        m.year,
        m.month,
        m.day,
        m.ts_base_event,
        m.conversion_sk_event_type,
        m.conversion_sk_event_date,
        m.conversion_ts_event,
        dd_1.week_start AS base_week_start,
        dd_1.date AS base_date,
        dd_2.week_start AS conversion_week_start,
        dd_2.date AS conversion_date
    FROM
        matches AS m
    JOIN
        dw_public.dim_date AS dd_1
            ON m.sk_event_date = dd_1.sk_date
    JOIN
        dw_public.dim_date AS dd_2
            ON m.conversion_sk_event_date = dd_2.sk_date
),
ranked AS (
    SELECT
        sk_sale_demand_event,
        sk_event_date,
        sk_event_type,
        sk_booking,
        sk_offer,
        sk_house,
        sk_region,
        sk_buyer,
        sk_seller,
        sk_agent,
        sk_agent_work_contract,
        sk_business_unit,
        sk_broker_supply,
        sk_broker_demand,
        sk_secretariat_booking_creator,
        sk_secretariat_on_event,
        sk_last_secretariat,
        year,
        month,
        day,
        ts_base_event,
        conversion_sk_event_type,
        conversion_sk_event_date,
        conversion_ts_event,
        base_week_start,
        base_date,
        conversion_week_start,
        conversion_date,
        ROW_NUMBER() OVER (
            PARTITION BY
                sk_sale_demand_event,
                conversion_sk_event_type
            ORDER BY
                conversion_sk_event_date
        ) AS rn -- Only interested in the first conversion
    FROM
        joined
)
SELECT
    sk_sale_demand_event || '-' || conversion_sk_event_type AS sk_sale_cohort_conversion,
    sk_event_date AS sk_base_date,
    conversion_sk_event_date AS sk_conversion_date,
    (
        sk_event_type || '-' ||
        conversion_sk_event_type || '-' ||
        CAST(GREATEST(LEAST(DATEDIFF(conversion_week_start, base_week_start) / 7, 20), 0) AS INT) || '-' ||
        GREATEST(LEAST(DATEDIFF(conversion_date, base_date), 140), 0)
    ) AS sk_cohort_type,
    sk_booking,
    sk_offer,
    sk_house,
    sk_region,
    sk_buyer,
    sk_seller,
    sk_agent,
    sk_agent_work_contract,
    sk_business_unit,
    sk_broker_supply,
    sk_broker_demand,
    sk_secretariat_booking_creator,
    sk_secretariat_on_event,
    sk_last_secretariat,
    DATEDIFF(conversion_date, base_date) AS days_to_conversion,
    CAST((DATEDIFF(conversion_week_start, base_week_start) / 7) AS INT) AS week_number,
    year,
    month,
    day,
    ts_base_event,
    conversion_ts_event AS ts_conversion_event,
    NOW() AS ts_load
FROM
    ranked
WHERE
    rn = 1
