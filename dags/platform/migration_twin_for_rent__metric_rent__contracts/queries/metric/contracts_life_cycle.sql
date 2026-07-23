WITH base AS (
    SELECT
        c.sk_contract,
        h.sk_region,
        t.id_termination,
        COALESCE(c.country_code, 'Undefined') AS country_code,
        COALESCE(r.city_group, 'Undefined') AS city_group,
        COALESCE(r.tier, 'Undefined') AS tier,
        c.status,
        t.status AS termination_status,
        c.ts_created,
        t.ts_created AS ts_termination_created,
        c.dt_start AS dt_started,
        c.dt_entrance,
        c.dt_annulment,
        c.ts_signature,
        c.ts_canceled,
        t.ts_canceled AS ts_termination_canceled,
        t.dt_ended_termination
    FROM
        dw_rent.dim_contract AS c
    LEFT JOIN
        dw_rent.fact_house_listings AS h
            ON c.sk_contract = h.sk_contract
    LEFT JOIN
        dw_public.dim_region AS r
            ON h.sk_region = r.sk_region
    LEFT JOIN
        datalake_offboarding.contract_termination AS t
            ON c.sk_contract = t.id_contract
),
-- As we may have different country code, city groups, tiers and dates in each type of event, it's necessary to cross join all options
-- in order to make sure that every combination will be available.
dimensions AS (
    SELECT DISTINCT
        COALESCE(r.country_code, 'Undefined') AS country_code,
        COALESCE(r.city_group, 'Undefined') AS city_group,
        COALESCE(r.tier, 'Undefined') AS tier,
        d.date AS dt_day,
        d.week_start AS dt_week_started,
        d.month_start AS dt_month
    FROM
        dw_public.dim_region AS r
    CROSS JOIN
        dw_public.dim_date AS d
    WHERE
        d.year BETWEEN 2015 AND YEAR(CURRENT_DATE)
),
new_contracts_signed AS (
    SELECT
        COUNT(DISTINCT sk_contract) AS new_contracts_signed,
        country_code,
        city_group,
        tier,
        COALESCE(DATE(ts_signature), dt_started) AS dt_day
    FROM
        base
    WHERE
        status IN ('Ativo', 'Finalizado')
        AND (ts_signature IS NOT NULL
            OR dt_started IS NOT NULL)
    GROUP BY 2, 3, 4, 5
),
new_rentals AS (
    SELECT
        COUNT(DISTINCT sk_contract) AS new_rentals,
        country_code,
        city_group,
        tier,
        COALESCE(dt_started, dt_entrance) AS dt_day
    FROM
        base
    WHERE
        status IN ('Ativo', 'Finalizado') -- Consider only contracts that are active or were active at a given period
        AND (dt_started IS NOT NULL
            OR dt_entrance IS NOT NULL)
        AND DATE(COALESCE(dt_started, dt_entrance)) < CURRENT_DATE -- We may have future dates for contract's start date
        AND (DATE(COALESCE(dt_started, dt_entrance)) < dt_annulment
            OR dt_annulment IS NULL)
    GROUP BY 2, 3, 4, 5
),
terminations_created AS (
    SELECT
        COUNT(DISTINCT id_termination) AS terminations_created,
        country_code,
        city_group,
        tier,
        DATE(ts_termination_created) AS dt_day
    FROM
        base
    WHERE
        ts_termination_created IS NOT NULL
    GROUP BY 2, 3, 4, 5
),
terminations_canceled AS (
    SELECT
        COUNT(DISTINCT id_termination) AS terminations_canceled,
        country_code,
        city_group,
        tier,
        DATE(ts_termination_canceled) AS dt_day
    FROM
        base
    WHERE
        ts_termination_canceled IS NOT NULL
        AND termination_status = 'CANCELED'
    GROUP BY 2, 3, 4, 5
),
terminations_ended AS (
    SELECT
        COUNT(DISTINCT id_termination) AS terminations_ended,
        country_code,
        city_group,
        tier,
        dt_ended_termination AS dt_day
    FROM
        base
    WHERE
        status = 'Finalizado'
        AND termination_status = 'DONE'
        AND dt_ended_termination IS NOT NULL
    GROUP BY 2, 3, 4, 5
),
ended_rentals AS (
    SELECT
        COUNT(DISTINCT sk_contract) AS ended_rentals,
        country_code,
        city_group,
        tier,
        dt_annulment AS dt_day
    FROM
        base
    WHERE
        status = 'Finalizado'
        AND dt_annulment IS NOT NULL
        AND dt_annulment < CURRENT_DATE
    GROUP BY 2, 3, 4, 5
)
SELECT DISTINCT
    d.country_code,
    COALESCE(d.city_group, 'Undefined') AS city_group,
    COALESCE(d.tier, 'Undefined') AS tier,
    COALESCE(new_contracts_signed, 0) AS new_contracts_signed,
    COALESCE(new_rentals, 0) AS new_rentals,
    COALESCE(terminations_created, 0) AS terminations_created,
    COALESCE(terminations_canceled, 0) AS terminations_canceled,
    COALESCE(terminations_ended, 0) AS terminations_ended,
    COALESCE(ended_rentals, 0) AS ended_rentals,
    d.dt_day,
    d.dt_week_started,
    d.dt_month
FROM
    dimensions AS d
LEFT JOIN
    new_contracts_signed AS ncs
        ON d.dt_day = ncs.dt_day
        AND d.country_code = ncs.country_code
        AND d.city_group = ncs.city_group
        AND d.tier = ncs.tier
LEFT JOIN
    new_rentals AS nr
        ON nr.country_code = d.country_code
        AND nr.city_group = d.city_group
        AND nr.tier = d.tier
        AND nr.dt_day = d.dt_day
LEFT JOIN
    terminations_created AS tc
        ON d.country_code = tc.country_code
        AND d.city_group = tc.city_group
        AND d.tier = tc.tier
        AND d.dt_day = tc.dt_day
LEFT JOIN
    terminations_canceled AS tcl
        ON tcl.country_code = d.country_code
        AND tcl.city_group = d.city_group
        AND tcl.tier = d.tier
        AND tcl.dt_day = d.dt_day
LEFT JOIN
    terminations_ended AS te
        ON d.country_code = te.country_code
        AND d.city_group = te.city_group
        AND d.tier = te.tier
        AND d.dt_day = te.dt_day
LEFT JOIN
    ended_rentals AS er
        ON er.country_code = d.country_code
        AND er.city_group = d.city_group
        AND er.tier = d.tier
        AND er.dt_day = d.dt_day
