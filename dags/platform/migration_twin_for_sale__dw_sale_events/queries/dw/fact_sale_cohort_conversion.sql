SELECT
    fee_1.sk_sale_demand_event || '-' || fee_2.sk_event_type AS sk_sale_cohort_conversion,
    fee_1.sk_event_date AS sk_base_date,
    fee_2.sk_event_date AS sk_conversion_date,
    (
        fee_1.sk_event_type || '-' ||
        fee_2.sk_event_type || '-' ||
        GREATEST(LEAST(DATEDIFF(dd_2.week_start, dd_1.week_start) / 7, 20), 0) :: INT || '-' ||
        GREATEST(LEAST(DATEDIFF(dd_2.date, dd_1.date), 140), 0)
    ) AS sk_cohort_type,
    fee_1.sk_booking,
    fee_1.sk_offer,
    fee_1.sk_house,
    fee_1.sk_region,
    fee_1.sk_buyer,
    fee_1.sk_seller,
    fee_1.sk_agent,
    fee_1.sk_agent_work_contract,
    fee_1.sk_business_unit,
    fee_1.sk_company_supply,
    fee_1.sk_company_demand,
    fee_1.sk_broker_supply,
    fee_1.sk_broker_demand,
    fee_1.sk_secretariat_booking_creator,
    fee_1.sk_secretariat_on_event,
    fee_1.sk_last_secretariat,
    DATEDIFF(dd_2.date, dd_1.date) AS days_to_conversion,
    (DATEDIFF(dd_2.week_start, dd_1.week_start) / 7) :: INT AS week_number,
    fee_1.year,
    fee_1.month,
    fee_1.day,
    fee_1.ts_event AS ts_base_event,
    fee_2.ts_event AS ts_conversion_event,
    NOW() AS ts_load
FROM
    dw_sale.fact_sale_demand_event AS fee_1
JOIN
    dw_public.dim_date AS dd_1
        ON fee_1.sk_event_date = dd_1.sk_date
JOIN
    dw_sale.fact_sale_demand_event AS fee_2
        ON (
            (fee_1.sk_offer::STRING = '-1' AND fee_1.sk_booking = fee_2.sk_booking) -- If the first event is booking related, we use booking as key
            OR (fee_1.sk_offer::STRING != '-1' AND fee_1.sk_offer = fee_2.sk_offer) -- Otherwise, use offer as key
        )
        AND fee_1.sk_event_type != fee_2.sk_event_type
JOIN
    dw_public.dim_date AS dd_2
        ON fee_2.sk_event_date = dd_2.sk_date
QUALIFY
    ROW_NUMBER() OVER (
        PARTITION BY
            fee_1.sk_sale_demand_event,
            fee_2.sk_event_type
        ORDER BY
            fee_2.sk_event_date
    ) = 1 -- Only interested in the first conversion