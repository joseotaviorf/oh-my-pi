-- Cohort days are 7, 2, or 8 days after the scheduled visit date, depending on the branch.
-- Anchoring on them (instead of CURRENT_DATE) keeps the result reproducible on backfills.
WITH last_visit AS (
    SELECT
        id_visitor,
        MAX(ts_schedule_visit) AS last_dt_scheduling
    FROM
        datalake_visit.visit_schedules
    WHERE
        ts_schedule_visit >= DATE_SUB(DATE('{load_start_date}'), 30)
    GROUP BY
        1
),
first_ AS (
    SELECT
        first_visit.id_visitor,
        first_visit.id_schedule AS sk_booking,
        last_visit.last_dt_scheduling,
        DATE_ADD(DATE(first_visit.ts_schedule_visit), 7) AS dt_cohort
    FROM
        datalake_visit.visit_schedules AS first_visit
    INNER JOIN
        last_visit
            ON last_visit.id_visitor = first_visit.id_visitor
            AND last_visit.last_dt_scheduling = first_visit.ts_schedule_visit
    WHERE
        first_visit.business_context = 'SALE'
        AND (
            first_visit.is_canceled
            OR first_visit.id_succeed_schedule IS NOT NULL
        )
        AND first_visit.schedule_origin = 'REQUEST'
),
second_ AS (
    SELECT
        first_visit.id_visitor,
        first_visit.id_schedule AS sk_booking,
        last_visit.last_dt_scheduling,
        DATE_ADD(DATE(first_visit.ts_schedule_visit), 2) AS dt_cohort
    FROM
        datalake_visit.visit_schedules AS first_visit
    INNER JOIN
        last_visit
            ON last_visit.id_visitor = first_visit.id_visitor
            AND last_visit.last_dt_scheduling = first_visit.ts_schedule_visit
    WHERE
        first_visit.business_context = 'SALE'
        AND NOT (
            first_visit.id_succeed_schedule IS NOT NULL
            OR first_visit.is_canceled
            OR first_visit.is_completed
            OR first_visit.is_unsuccessful
        )
        AND first_visit.schedule_origin = 'REQUEST'
),
third_ AS (
    SELECT
        first_visit.id_visitor,
        first_visit.id_schedule AS sk_booking,
        last_visit.last_dt_scheduling,
        DATE_ADD(DATE(first_visit.ts_schedule_visit), 8) AS dt_cohort
    FROM
        datalake_visit.visit_schedules AS first_visit
    INNER JOIN
        last_visit
            ON last_visit.id_visitor = first_visit.id_visitor
            AND last_visit.last_dt_scheduling = first_visit.ts_schedule_visit
    LEFT JOIN
        dw_sale.fact_offers AS o
            ON first_visit.id_visitor = o.sk_buyer
            AND o.ts_offer_submitted > first_visit.ts_schedule_visit
    WHERE
        first_visit.business_context = 'SALE'
        AND (
            first_visit.is_completed
            OR first_visit.is_unsuccessful
        )
        AND first_visit.schedule_origin = 'REQUEST'
        AND o.ts_offer_submitted IS NULL
),
rent_visits AS (
    SELECT
        id_visitor,
        MAX(ts_visit) AS dt_visit_rent
    FROM
        datalake_visit.visits
    WHERE
        business_context = 'RENT'
        AND is_completed
    GROUP BY
        1
),
union_ AS (
    SELECT
        id_visitor,
        sk_booking,
        last_dt_scheduling,
        dt_cohort
    FROM
        first_
    UNION ALL
    SELECT
        id_visitor,
        sk_booking,
        last_dt_scheduling,
        dt_cohort
    FROM
        second_
    UNION ALL
    SELECT
        id_visitor,
        sk_booking,
        last_dt_scheduling,
        dt_cohort
    FROM
        third_
),
previous_dispatches AS (
    SELECT DISTINCT
        customer_email,
        MAKE_DATE(year, month, day) AS dt_partition
    FROM
        reverse_tracksale_test.lost_buyer_visits
    WHERE
        is_dispatched = TRUE
        AND customer_email IS NOT NULL
        AND MAKE_DATE(year, month, day) >= DATE_SUB(DATE('{load_start_date}'), 90)
    UNION
    SELECT DISTINCT
        customer_email,
        MAKE_DATE(year, month, day) AS dt_partition
    FROM
        datalake_tracksale_reverse.lost_buyer_visits
    WHERE
        is_dispatched = TRUE
        AND customer_email IS NOT NULL
        AND MAKE_DATE(year, month, day) >= DATE_SUB(DATE('{load_start_date}'), 90)
)
SELECT
    du.nome AS customer_name,
    du.email AS customer_email,
    du.telefone_principal AS customer_phone,
    'Visita' AS campaign_step,
    'Buyer' AS customer_type,
    du.cpf AS customer_cpf,
    v.id_visitor AS id_user,
    'lost' AS campaign_type,
    'booking' AS driver_type,
    v.sk_booking AS id_driver,
    CASE
        WHEN rv.id_visitor IS NULL THEN 'Sale'
        ELSE 'Híbrido'
    END AS business_context,
    CASE
        WHEN pd.customer_email IS NOT NULL THEN TRUE
        ELSE FALSE
    END AS is_dispatched,
    CASE
        WHEN pd.customer_email IS NOT NULL THEN CAST(DATE('{load_start_date}') AS TIMESTAMP)
        ELSE CAST(NULL AS TIMESTAMP)
    END AS ts_dispatched,
    v.dt_cohort,
    YEAR(v.dt_cohort) AS year,
    MONTH(v.dt_cohort) AS month,
    DAY(v.dt_cohort) AS day
FROM
    union_ AS v
JOIN
    dw_public.dim_user AS du
        ON du.sk_user = v.id_visitor
LEFT JOIN
    rent_visits AS rv
        ON rv.id_visitor = v.id_visitor
        AND rv.dt_visit_rent BETWEEN (
            v.last_dt_scheduling - INTERVAL '30' DAY
        ) AND (
            v.last_dt_scheduling + INTERVAL '30' DAY
        )
LEFT JOIN
    previous_dispatches AS pd
        ON du.email = pd.customer_email
        AND pd.dt_partition BETWEEN DATE_SUB(v.dt_cohort, 90) AND v.dt_cohort
WHERE
    v.dt_cohort BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
