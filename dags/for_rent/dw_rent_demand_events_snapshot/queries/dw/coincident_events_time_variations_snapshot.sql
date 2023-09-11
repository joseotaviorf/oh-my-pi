WITH metrics_d1 AS (
    SELECT
        'D-1' AS reference_type,
        business_type,
        rent_flow_origin,
        SUM(visits_booked) AS visits_booked,
        NULL AS diff_vb,
        NULL AS percentage_diff_vb,
        SUM(visits_completed) AS visits_completed,
        NULL AS diff_vc,
        NULL AS percentage_diff_vc,
        SUM(offers_submitted) AS offers_submitted,
        NULL AS diff_os,
        NULL AS percentage_diff_os,
        SUM(offers_accepted) AS offers_accepted,
        NULL AS diff_oa,
        NULL AS percentage_diff_oa,
        SUM(evaluation_started) AS evaluation_started,
        NULL AS diff_es,
        NULL AS percentage_diff_es,
        SUM(evaluation_positive) AS evaluation_positive,
        NULL AS diff_ep,
        NULL AS percentage_diff_ep,
        SUM(documentation_sent) AS documentation_sent,
        NULL AS diff_ds,
        NULL AS percentage_diff_ds,
        SUM(credit_approved) AS credit_approved,
        NULL AS diff_ca,
        NULL AS percentage_diff_ca,
        SUM(contracts_signed) AS contracts_signed,
        NULL AS diff_cs,
        NULL AS percentage_diff_cs,
        DATE(dt_event) AS dt_reference,
        DATE(ts_snapshot) AS dt_snapshot,
        country_code,
        year,
        month,
        day
    FROM
        dw_rent_snapshot.rent_demand_events_snapshot
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
        AND dt_event = DATE_ADD(DATE('{year}-{month}-{day}'), -1)
    GROUP BY 1, 2, 3, 31, 32, 33, 34, 35, 36
),
metrics_5w AS (
    SELECT
        'W1-W5' AS reference_type,
        business_type,
        rent_flow_origin,
        SUM(visits_booked) AS visits_booked,
        SUM(visits_completed) AS visits_completed,
        SUM(offers_submitted) AS offers_submitted,
        SUM(offers_accepted) AS offers_accepted,
        SUM(evaluation_started) AS evaluation_started,
        SUM(evaluation_positive) AS evaluation_positive,
        SUM(documentation_sent) AS documentation_sent,
        SUM(credit_approved) AS credit_approved,
        SUM(contracts_signed) AS contracts_signed,
        DATE_TRUNC('week', dt_event) AS dt_reference,
        DATE(ts_snapshot) AS dt_snapshot,
        country_code,
        year,
        month,
        day
    FROM
        dw_rent_snapshot.rent_demand_events_snapshot
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
        AND DATE_TRUNC('week', dt_event)
            BETWEEN DATE_TRUNC('week', DATE_ADD(DATE('{year}-{month}-{day}'), -35))
                AND DATE_TRUNC('week', DATE_ADD(DATE('{year}-{month}-{day}'), -7)) -- Between -1 to -5 weeks
    GROUP BY 1, 2, 3, 13, 14, 15, 16, 17, 18
),
divergences_5w AS (
    SELECT
        'W1-W5' AS reference_type,
        business_type,
        rent_flow_origin,
        SUM(visits_booked) AS visits_booked,
        SUM(visits_completed) AS visits_completed,
        SUM(offers_submitted) AS offers_submitted,
        SUM(offers_accepted) AS offers_accepted,
        SUM(evaluation_started) AS evaluation_started,
        SUM(evaluation_positive) AS evaluation_positive,
        SUM(documentation_sent) AS documentation_sent,
        SUM(credit_approved) AS credit_approved,
        SUM(contracts_signed) AS contracts_signed,
        DATE_TRUNC('week', dt_event) AS dt_reference,
        DATE(ts_snapshot) AS dt_snapshot,
        country_code,
        year,
        month,
        day
    FROM
        dw_rent_snapshot.rent_demand_events_snapshot AS r
    WHERE
        DATE(ts_snapshot) = DATE_TRUNC('week', DATE_ADD(dt_event, 7)) -- The snapshot should be from the week start of the following week
        AND DATE_TRUNC('week', dt_event)
            BETWEEN DATE_TRUNC('week', DATE_ADD(DATE('{year}-{month}-{day}'), -35))
                AND DATE_TRUNC('week', DATE_ADD(DATE('{year}-{month}-{day}'), -7)) -- Between -1 to -5 weeks
    GROUP BY 1, 2, 3, 13, 14, 15, 16, 17, 18
),
final_5w AS (
    SELECT
        m.reference_type,
        m.business_type,
        m.rent_flow_origin,
        m.visits_booked,
        m.visits_booked-d.visits_booked AS diff_vb,
        COALESCE(ROUND(100*(1-(m.visits_booked/d.visits_booked)), 2), 0) AS percentage_diff_vb,
        m.visits_completed,
        m.visits_completed-d.visits_completed AS diff_vc,
        COALESCE(ROUND(100*(1-(m.visits_completed/d.visits_completed)), 2), 0) AS percentage_diff_vc,
        m.offers_submitted,
        m.offers_submitted-d.offers_submitted AS diff_os,
        COALESCE(ROUND(100*(1-(m.offers_submitted/d.offers_submitted)), 2), 0) AS percentage_diff_os,
        m.offers_accepted,
        m.offers_accepted-d.offers_accepted AS diff_oa,
        COALESCE(ROUND(100*(1-(m.offers_accepted/d.offers_accepted)), 2), 0) AS percentage_diff_oa,
        m.evaluation_started,
        m.evaluation_started-d.evaluation_started AS diff_es,
        COALESCE(ROUND(100*(1-(m.evaluation_started/d.evaluation_started)), 2), 0) AS percentage_diff_es,
        m.evaluation_positive,
        m.evaluation_positive-d.evaluation_positive AS diff_ep,
        COALESCE(ROUND(100*(1-(m.evaluation_positive/d.evaluation_positive)), 2), 0) AS percentage_diff_ep,
        m.documentation_sent,
        m.documentation_sent-d.documentation_sent AS diff_ds,
        COALESCE(ROUND(100*(1-(m.documentation_sent/d.documentation_sent)), 2), 0) AS percentage_diff_ds,
        m.credit_approved,
        m.credit_approved-d.credit_approved AS diff_ca,
        COALESCE(ROUND(100*(1-(m.credit_approved/d.credit_approved)), 2), 0) AS percentage_diff_ca,
        m.contracts_signed,
        m.contracts_signed-d.contracts_signed AS diff_cs,
        COALESCE(ROUND(100*(1-(m.contracts_signed/d.contracts_signed)), 2), 0) AS percentage_diff_cs,
        DATE(m.dt_reference) AS dt_reference,
        m.dt_snapshot,
        m.country_code,
        m.year,
        m.month,
        m.day
    FROM
        metrics_5w AS m
    JOIN
        divergences_5w AS d
            ON d.country_code = m.country_code
            AND d.dt_reference = m.dt_reference
            AND d.business_type = m.business_type
            AND d.rent_flow_origin = m.rent_flow_origin
),
metrics_m AS (
    SELECT
        'LM' AS reference_type,
        business_type,
        rent_flow_origin,
        SUM(visits_booked) AS visits_booked,
        SUM(visits_completed) AS visits_completed,
        SUM(offers_submitted) AS offers_submitted,
        SUM(offers_accepted) AS offers_accepted,
        SUM(evaluation_started) AS evaluation_started,
        SUM(evaluation_positive) AS evaluation_positive,
        SUM(documentation_sent) AS documentation_sent,
        SUM(credit_approved) AS credit_approved,
        SUM(contracts_signed) AS contracts_signed,
        DATE_TRUNC('month', dt_event) AS dt_reference,
        DATE(ts_snapshot) AS dt_snapshot,
        country_code,
        year,
        month,
        day
    FROM
        dw_rent_snapshot.rent_demand_events_snapshot
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
        AND DATE_TRUNC('month', dt_event) = DATE_TRUNC('month', ADD_MONTHS(DATE('{year}-{month}-{day}'), -1))  -- Gets the events truncated by the beginning of the previous month
    GROUP BY 1, 2, 3, 13, 14, 15, 16, 17, 18
),
divergences_m AS (
    SELECT
        'LM' AS reference_type,
        business_type,
        rent_flow_origin,
        SUM(visits_booked) AS visits_booked,
        SUM(visits_completed) AS visits_completed,
        SUM(offers_submitted) AS offers_submitted,
        SUM(offers_accepted) AS offers_accepted,
        SUM(evaluation_started) AS evaluation_started,
        SUM(evaluation_positive) AS evaluation_positive,
        SUM(documentation_sent) AS documentation_sent,
        SUM(credit_approved) AS credit_approved,
        SUM(contracts_signed) AS contracts_signed,
        DATE_TRUNC('month', dt_event) AS dt_reference,
        DATE(ts_snapshot) AS dt_snapshot,
        country_code,
        year,
        month,
        day
    FROM
        dw_rent_snapshot.rent_demand_events_snapshot AS r
    WHERE
        DATE(ts_snapshot) = DATE(DATE_TRUNC('month', DATE('{year}-{month}-{day}')))  -- Gets the snapshot of the first day of the next month (it'll have data of the whole previous month, til its last day)
        AND DATE(DATE_TRUNC('month', dt_event)) = DATE_TRUNC('month', (ADD_MONTHS(DATE('{year}-{month}-{day}'), -1)))  -- Gets the events truncated by the previous month start date
    GROUP BY 1, 2, 3, 13, 14, 15, 16, 17, 18
),
final_m AS (
    SELECT
        m.reference_type,
        m.business_type,
        m.rent_flow_origin,
        m.visits_booked,
        m.visits_booked-d.visits_booked AS diff_vb,
        COALESCE(ROUND(100*(1-(m.visits_booked/d.visits_booked)), 2), 0) AS percentage_diff_vb,
        m.visits_completed,
        m.visits_completed-d.visits_completed AS diff_vc,
        COALESCE(ROUND(100*(1-(m.visits_completed/d.visits_completed)), 2), 0) AS percentage_diff_vc,
        m.offers_submitted,
        m.offers_submitted-d.offers_submitted AS diff_os,
        COALESCE(ROUND(100*(1-(m.offers_submitted/d.offers_submitted)), 2), 0) AS percentage_diff_os,
        m.offers_accepted,
        m.offers_accepted-d.offers_accepted AS diff_oa,
        COALESCE(ROUND(100*(1-(m.offers_accepted/d.offers_accepted)), 2), 0) AS percentage_diff_oa,
        m.evaluation_started,
        m.evaluation_started-d.evaluation_started AS diff_es,
        COALESCE(ROUND(100*(1-(m.evaluation_started/d.evaluation_started)), 2), 0) AS percentage_diff_es,
        m.evaluation_positive,
        m.evaluation_positive-d.evaluation_positive AS diff_ep,
        COALESCE(ROUND(100*(1-(m.evaluation_positive/d.evaluation_positive)), 2), 0) AS percentage_diff_ep,
        m.documentation_sent,
        m.documentation_sent-d.documentation_sent AS diff_ds,
        COALESCE(ROUND(100*(1-(m.documentation_sent/d.documentation_sent)), 2), 0) AS percentage_diff_ds,
        m.credit_approved,
        m.credit_approved-d.credit_approved AS diff_ca,
        COALESCE(ROUND(100*(1-(m.credit_approved/d.credit_approved)), 2), 0) AS percentage_diff_ca,
        m.contracts_signed,
        m.contracts_signed-d.contracts_signed AS diff_cs,
        COALESCE(ROUND(100*(1-(m.contracts_signed/d.contracts_signed)), 2), 0) AS percentage_diff_cs,
        DATE(m.dt_reference) AS dt_reference,
        m.dt_snapshot,
        m.country_code,
        m.year,
        m.month,
        m.day
    FROM
        metrics_m AS m
    JOIN
        divergences_m AS d
            ON d.country_code = m.country_code
            AND d.dt_reference = m.dt_reference
            AND d.business_type = m.business_type
            AND d.rent_flow_origin = m.rent_flow_origin
),
metrics_q AS (
    SELECT
        'LQ' AS reference_type,
        business_type,
        rent_flow_origin,
        SUM(visits_booked) AS visits_booked,
        SUM(visits_completed) AS visits_completed,
        SUM(offers_submitted) AS offers_submitted,
        SUM(offers_accepted) AS offers_accepted,
        SUM(evaluation_started) AS evaluation_started,
        SUM(evaluation_positive) AS evaluation_positive,
        SUM(documentation_sent) AS documentation_sent,
        SUM(credit_approved) AS credit_approved,
        SUM(contracts_signed) AS contracts_signed,
        DATE_TRUNC('quarter', dt_event) AS dt_reference,
        DATE(ts_snapshot) AS dt_snapshot,
        country_code,
        year,
        month,
        day
    FROM
        dw_rent_snapshot.rent_demand_events_snapshot
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
        AND DATE_TRUNC('quarter', dt_event) = DATE_TRUNC('quarter', ADD_MONTHS(DATE('{year}-{month}-{day}'), -3))  -- Gets the events truncated by the beginning of the previous quarter
    GROUP BY 1, 2, 3, 13, 14, 15, 16, 17, 18
),
divergences_q AS (
    SELECT
        'LQ' AS reference_type,
        business_type,
        rent_flow_origin,
        SUM(visits_booked) AS visits_booked,
        SUM(visits_completed) AS visits_completed,
        SUM(offers_submitted) AS offers_submitted,
        SUM(offers_accepted) AS offers_accepted,
        SUM(evaluation_started) AS evaluation_started,
        SUM(evaluation_positive) AS evaluation_positive,
        SUM(documentation_sent) AS documentation_sent,
        SUM(credit_approved) AS credit_approved,
        SUM(contracts_signed) AS contracts_signed,
        DATE_TRUNC('quarter', dt_event) AS dt_reference,
        DATE(ts_snapshot) AS dt_snapshot,
        country_code,
        year,
        month,
        day
    FROM
        dw_rent_snapshot.rent_demand_events_snapshot AS r
    WHERE
        DATE(ts_snapshot) = DATE(DATE_TRUNC('quarter', DATE('{year}-{month}-{day}')))    -- Gets the snapshot of the first day of the next quarter (it'll have data of the whole previous quarter, til its last day)
        AND DATE(DATE_TRUNC('quarter', dt_event)) = DATE_TRUNC('quarter', (ADD_MONTHS(DATE('{year}-{month}-{day}'), -3)))  -- Gets the events truncated by the previous quarter start date
    GROUP BY 1, 2, 3, 13, 14, 15, 16, 17, 18
),
final_q AS (
    SELECT
        m.reference_type,
        m.business_type,
        m.rent_flow_origin,
        m.visits_booked,
        m.visits_booked-d.visits_booked AS diff_vb,
        COALESCE(ROUND(100*(1-(m.visits_booked/d.visits_booked)), 2), 0) AS percentage_diff_vb,
        m.visits_completed,
        m.visits_completed-d.visits_completed AS diff_vc,
        COALESCE(ROUND(100*(1-(m.visits_completed/d.visits_completed)), 2), 0) AS percentage_diff_vc,
        m.offers_submitted,
        m.offers_submitted-d.offers_submitted AS diff_os,
        COALESCE(ROUND(100*(1-(m.offers_submitted/d.offers_submitted)), 2), 0) AS percentage_diff_os,
        m.offers_accepted,
        m.offers_accepted-d.offers_accepted AS diff_oa,
        COALESCE(ROUND(100*(1-(m.offers_accepted/d.offers_accepted)), 2), 0) AS percentage_diff_oa,
        m.evaluation_started,
        m.evaluation_started-d.evaluation_started AS diff_es,
        COALESCE(ROUND(100*(1-(m.evaluation_started/d.evaluation_started)), 2), 0) AS percentage_diff_es,
        m.evaluation_positive,
        m.evaluation_positive-d.evaluation_positive AS diff_ep,
        COALESCE(ROUND(100*(1-(m.evaluation_positive/d.evaluation_positive)), 2), 0) AS percentage_diff_ep,
        m.documentation_sent,
        m.documentation_sent-d.documentation_sent AS diff_ds,
        COALESCE(ROUND(100*(1-(m.documentation_sent/d.documentation_sent)), 2), 0) AS percentage_diff_ds,
        m.credit_approved,
        m.credit_approved-d.credit_approved AS diff_ca,
        COALESCE(ROUND(100*(1-(m.credit_approved/d.credit_approved)), 2), 0) AS percentage_diff_ca,
        m.contracts_signed,
        m.contracts_signed-d.contracts_signed AS diff_cs,
        COALESCE(ROUND(100*(1-(m.contracts_signed/d.contracts_signed)), 2), 0) AS percentage_diff_cs,
        DATE(m.dt_reference) AS dt_reference,
        m.dt_snapshot,
        m.country_code,
        m.year,
        m.month,
        m.day
    FROM
        metrics_q AS m
    JOIN
        divergences_q AS d
            ON d.country_code = m.country_code
            AND d.dt_reference = m.dt_reference
            AND d.business_type = m.business_type
            AND d.rent_flow_origin = m.rent_flow_origin
),
metrics_y AS (
    SELECT
        'LY' AS reference_type,
        business_type,
        rent_flow_origin,
        SUM(visits_booked) AS visits_booked,
        SUM(visits_completed) AS visits_completed,
        SUM(offers_submitted) AS offers_submitted,
        SUM(offers_accepted) AS offers_accepted,
        SUM(evaluation_started) AS evaluation_started,
        SUM(evaluation_positive) AS evaluation_positive,
        SUM(documentation_sent) AS documentation_sent,
        SUM(credit_approved) AS credit_approved,
        SUM(contracts_signed) AS contracts_signed,
        DATE_TRUNC('year', dt_event) AS dt_reference,
        DATE(ts_snapshot) AS dt_snapshot,
        country_code,
        year,
        month,
        day
    FROM
        dw_rent_snapshot.rent_demand_events_snapshot
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
        AND DATE_TRUNC('year', dt_event) = DATE_TRUNC('year', ADD_MONTHS(DATE('{year}-{month}-{day}'), -12))   -- Gets the events truncated by the beginning of the previous year
    GROUP BY 1, 2, 3, 13, 14, 15, 16, 17, 18
),
divergences_y AS (
    SELECT
        'LY' AS reference_type,
        business_type,
        rent_flow_origin,
        SUM(visits_booked) AS visits_booked,
        SUM(visits_completed) AS visits_completed,
        SUM(offers_submitted) AS offers_submitted,
        SUM(offers_accepted) AS offers_accepted,
        SUM(evaluation_started) AS evaluation_started,
        SUM(evaluation_positive) AS evaluation_positive,
        SUM(documentation_sent) AS documentation_sent,
        SUM(credit_approved) AS credit_approved,
        SUM(contracts_signed) AS contracts_signed,
        DATE_TRUNC('year', dt_event) AS dt_reference,
        DATE(ts_snapshot) AS dt_snapshot,
        country_code,
        r.year,
        r.month,
        r.day
    FROM
        dw_rent_snapshot.rent_demand_events_snapshot AS r
    JOIN
        dw_public.dim_date AS d
            ON d.date = r.dt_event
    WHERE
        DATE(ts_snapshot) = DATE(DATE_TRUNC('year', DATE('{year}-{month}-{day}')))   -- Gets the snapshot of the first day of the year (it'll have data of the whole previous year, til its last day)
        AND DATE(DATE_TRUNC('year', dt_event)) = MAKE_DATE(YEAR(d.last_year), 1, 1)   -- Gets the events truncated by the previous year start date
    GROUP BY 1, 2, 3, 13, 14, 15, 16, 17, 18
),
final_y AS (
    SELECT
        m.reference_type,
        m.business_type,
        m.rent_flow_origin,
        m.visits_booked,
        m.visits_booked-d.visits_booked AS diff_vb,
        COALESCE(ROUND(100*(1-(m.visits_booked/d.visits_booked)), 2), 0) AS percentage_diff_vb,
        m.visits_completed,
        m.visits_completed-d.visits_completed AS diff_vc,
        COALESCE(ROUND(100*(1-(m.visits_completed/d.visits_completed)), 2), 0) AS percentage_diff_vc,
        m.offers_submitted,
        m.offers_submitted-d.offers_submitted AS diff_os,
        COALESCE(ROUND(100*(1-(m.offers_submitted/d.offers_submitted)), 2), 0) AS percentage_diff_os,
        m.offers_accepted,
        m.offers_accepted-d.offers_accepted AS diff_oa,
        COALESCE(ROUND(100*(1-(m.offers_accepted/d.offers_accepted)), 2), 0) AS percentage_diff_oa,
        m.evaluation_started,
        m.evaluation_started-d.evaluation_started AS diff_es,
        COALESCE(ROUND(100*(1-(m.evaluation_started/d.evaluation_started)), 2), 0) AS percentage_diff_es,
        m.evaluation_positive,
        m.evaluation_positive-d.evaluation_positive AS diff_ep,
        COALESCE(ROUND(100*(1-(m.evaluation_positive/d.evaluation_positive)), 2), 0) AS percentage_diff_ep,
        m.documentation_sent,
        m.documentation_sent-d.documentation_sent AS diff_ds,
        COALESCE(ROUND(100*(1-(m.documentation_sent/d.documentation_sent)), 2), 0) AS percentage_diff_ds,
        m.credit_approved,
        m.credit_approved-d.credit_approved AS diff_ca,
        COALESCE(ROUND(100*(1-(m.credit_approved/d.credit_approved)), 2), 0) AS percentage_diff_ca,
        m.contracts_signed,
        m.contracts_signed-d.contracts_signed AS diff_cs,
        COALESCE(ROUND(100*(1-(m.contracts_signed/d.contracts_signed)), 2), 0) AS percentage_diff_cs,
        DATE(m.dt_reference) AS dt_reference,
        m.dt_snapshot,
        m.country_code,
        m.year,
        m.month,
        m.day
    FROM
        metrics_y AS m
    JOIN
        divergences_y AS d
            ON d.country_code = m.country_code
            AND d.dt_reference = m.dt_reference
            AND d.business_type = m.business_type
            AND d.rent_flow_origin = m.rent_flow_origin
)
SELECT *, NOW() AS ts_load FROM metrics_d1
UNION ALL
SELECT *, NOW() AS ts_load FROM final_5w
UNION ALL
SELECT *, NOW() AS ts_load FROM final_m
UNION ALL
SELECT *, NOW() AS ts_load FROM final_q
UNION ALL
SELECT *, NOW() AS ts_load FROM final_y
