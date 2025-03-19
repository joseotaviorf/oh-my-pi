WITH intervals AS (
    SELECT
        dd.sk_date,
        sk_agent,
        sk_work_contract,
        sk_company,
        ROW_NUMBER() OVER(PARTITION BY sk_agent, dd.date ORDER BY ts_status_started DESC) = 1 AS is_last_status_of_day,
        dd.year,
        dd.month,
        dd.day,
        DATEDIFF(dd.date, ts_last_contract_changed) AS days_since_last_contract_changed,
        DATEDIFF(dd.date, ts_last_activation_changed) AS days_since_last_activation_changed,
        DATEDIFF(dd.date, ts_last_business_context_changed) AS days_since_last_business_context_changed,
        ts_status_started,
        ts_status_ended,
        dd.date
    FROM
        dw_agent.fact_agent_contract
    JOIN
        dw_public.dim_date AS dd
            ON dd.date BETWEEN DATE(ts_status_started) AND COALESCE(DATE(ts_status_ended), NOW())
    WHERE
        dd.year = {year}
        AND dd.month = {month}
        AND dd.day = {day}
),
agents_with_allocated_slots AS (
    SELECT
        sk_date,
        sk_agent,
        FIRST(sk_work_contract) AS sk_work_contract,
        FIRST(sk_company) AS sk_company,
        COALESCE(SUM(ash.allocated_slots), 0) AS allocated_slots,
        FIRST(days_since_last_contract_changed) AS days_since_last_contract_changed,
        FIRST(days_since_last_activation_changed) AS days_since_last_activation_changed,
        FIRST(days_since_last_business_context_changed) AS days_since_last_business_context_changed,
        FIRST(is_last_status_of_day) AS is_last_status_of_day,
        i.ts_status_started,
        FIRST(i.ts_status_ended) AS ts_status_ended,
        FIRST(i.date) AS date,
        FIRST(i.year) AS year,
        FIRST(i.month) AS month,
        FIRST(i.day) AS day
    FROM
        intervals AS i
    LEFT JOIN
        datalake_agenda_allocation.agents_slots_hourly AS ash
            ON ash.year = i.year
            AND ash.month = i.month
            AND ash.day = i.day
            AND ash.id_agent = i.sk_agent
            AND ash.ts_slot_hour BETWEEN GREATEST(ts_status_started, date) AND COALESCE(ts_status_ended, NOW())
    GROUP BY
        sk_date,
        sk_agent,
        ts_status_started
)
SELECT
    sk_date,
    sk_agent,
    sk_work_contract,
    sk_company,
    allocated_slots,
    days_since_last_contract_changed,
    days_since_last_activation_changed,
    days_since_last_business_context_changed,
    is_last_status_of_day,
    GREATEST(date::TIMESTAMP, ts_status_started) AS ts_validity_started,
    LEAST(date::TIMESTAMP + INTERVAL '1' DAYS, ts_status_ended) AS ts_validity_ended,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    agents_with_allocated_slots
