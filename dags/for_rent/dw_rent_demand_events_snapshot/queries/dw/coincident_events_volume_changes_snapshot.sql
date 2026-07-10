/** Brief disclaimer about the creation of this table:
    About the choosen partitions:
    In every DAG run, we want to look to an specific snapshot file, in order to compare the historical events.
    In our DAG run, we always have the D-1 date (for example, on the day 2023-09-13, the DAG run will be 2023-09-12).
    In every snapshot from rent_demand_events, we create it using the current date (for example, on the day 2023-09-13,
    the snapshot date will also be 2023-09-13).
    So in this case, if we used the DAG run date (purely year-month-day), we would have a D-1 date when the snapshot date is D.
    In order to avoid this behaviour, in every partition we're adding +1 day, so we'll be looking for the right snapshot file.

    About the checks of enough snapshots:
    In order to guarantee that we're doing a fair comparision of results, we decided to add some rules related to each time window vision.
    Related to the last 5 weeks metrics, we'll only bring the results if in these last 5 weeks (which has in total 35 days), we
    have at least 32 snapshots;
    Related to the last month metric, we'll only bring the results if in the last month (which has usually around 30 days), we
    have at least 26 snapshots;
    Related to the last quarter metric, we'll only bring the results if in the last quarter (which has usually around 90 days), we
    have at least 83 snapshots;
    Related to the last year metric, we'll only bring the results if in the last quarter (which has usually around 90 days), we
    have at least 340 snapshots.
**/
WITH metrics_d1 AS (
    SELECT
        'D-1' AS reference_type,
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
        MAKE_DATE(year, month, day) AS dt_snapshot,
        country_code,
        year,
        month,
        day
    FROM
        dw_rent_snapshot.rent_demand_events_snapshot
    WHERE
        MAKE_DATE(year, month, day) = DATE_ADD(DATE('{year}-{month}-{day}'), 1)   -- It's necessary to add 1 day because the execution date is always D-1 but we create the snapshot date based on the current day
        AND dt_event = DATE('{year}-{month}-{day}')   -- As the execution date is always D-1, it's exactly the event date that we want
    GROUP BY 1, 29, 30, 31, 32, 33, 34
),
checking_weekly_snapshots AS (
    -- Checking if we have at least 32 snapshots of the previous 5 weeks, which has 35 days in total
    SELECT
        'W1-W5' AS reference_type,
        IF(COUNT(DISTINCT MAKE_DATE(year, month, day)) > 31, TRUE, FALSE) AS has_enough_snapshots
    FROM
        dw_rent_snapshot.rent_demand_events_snapshot
    WHERE
        MAKE_DATE(year, month, day)
            BETWEEN DATE_TRUNC('week', DATE_ADD(DATE_ADD(DATE('{year}-{month}-{day}'), 1), -35))
                AND DATE_TRUNC('week', DATE_ADD(DATE('{year}-{month}-{day}'), 1))
),
metrics_5w AS (
    SELECT
        'W1-W5' AS reference_type,
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
        MAKE_DATE(year, month, day) AS dt_snapshot,
        country_code,
        year,
        month,
        day
    FROM
        dw_rent_snapshot.rent_demand_events_snapshot
    WHERE
        MAKE_DATE(year, month, day) = DATE_ADD(DATE('{year}-{month}-{day}'), 1)
        AND DATE_TRUNC('week', dt_event)
            BETWEEN DATE_TRUNC('week', DATE_ADD(DATE_ADD(DATE('{year}-{month}-{day}'), 1), -35))
                AND DATE_TRUNC('week', DATE_ADD(DATE_ADD(DATE('{year}-{month}-{day}'), 1), -7)) -- Between -1 to -5 weeks
    GROUP BY 1, 11, 13, 14, 15, 16
),
divergences_5w AS (
    SELECT
        'W1-W5' AS reference_type,
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
        MAKE_DATE(year, month, day) AS dt_snapshot,
        country_code,
        year,
        month,
        day
    FROM
        dw_rent_snapshot.rent_demand_events_snapshot AS r
    JOIN
        checking_weekly_snapshots AS c
            ON c.reference_type = 'W1-W5'
            AND c.has_enough_snapshots = TRUE
    WHERE
        MAKE_DATE(year, month, day) = DATE_TRUNC('week', DATE_ADD(dt_event, 7)) -- The snapshot should be from the week start of the following week
        AND DATE_TRUNC('week', dt_event)
            BETWEEN DATE_TRUNC('week', DATE_ADD(DATE_ADD(DATE('{year}-{month}-{day}'), 1), -35))
                AND DATE_TRUNC('week', DATE_ADD(DATE_ADD(DATE('{year}-{month}-{day}'), 1), -7)) -- Between -1 to -5 weeks
    GROUP BY 1, 11, 13, 14, 15, 16
),
final_5w AS (
    SELECT
        m.reference_type,
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
),
checking_monthly_snapshots AS (
    -- Checking if we have at least 26 snapshots of the previous month, since a month usually has around 30 days
    SELECT
        'LM' AS reference_type,
        IF(COUNT(DISTINCT MAKE_DATE(year, month, day)) > 25, TRUE, FALSE) AS has_enough_snapshots
    FROM
        dw_rent_snapshot.rent_demand_events_snapshot
    WHERE
        MAKE_DATE(year, month, day)
            BETWEEN DATE_TRUNC('month', ADD_MONTHS(DATE_ADD(DATE('{year}-{month}-{day}'), 1), -1))
            AND DATE_TRUNC('month', DATE_ADD(DATE('{year}-{month}-{day}'), 1))
),
metrics_m AS (
    SELECT
        'LM' AS reference_type,
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
        MAKE_DATE(year, month, day) AS dt_snapshot,
        country_code,
        year,
        month,
        day
    FROM
        dw_rent_snapshot.rent_demand_events_snapshot
    WHERE
        MAKE_DATE(year, month, day) = DATE_ADD(DATE('{year}-{month}-{day}'), 1)
        AND DATE_TRUNC('month', dt_event) = DATE_TRUNC('month', ADD_MONTHS(DATE_ADD(DATE('{year}-{month}-{day}'), 1), -1))  -- Gets the events truncated by the beginning of the previous month
    GROUP BY 1, 11, 13, 14, 15, 16
),
divergences_m AS (
    SELECT
        'LM' AS reference_type,
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
        MAKE_DATE(year, month, day) AS dt_snapshot,
        country_code,
        year,
        month,
        day
    FROM
        dw_rent_snapshot.rent_demand_events_snapshot AS r
    JOIN
        checking_monthly_snapshots AS c
            ON c.reference_type = 'LM'
            AND c.has_enough_snapshots = TRUE
    WHERE
        MAKE_DATE(year, month, day) = DATE(DATE_TRUNC('month', DATE_ADD(DATE('{year}-{month}-{day}'), 1)))  -- Gets the snapshot of the first day of the next month (it'll have data of the whole previous month, til its last day)
        AND DATE(DATE_TRUNC('month', dt_event)) = DATE_TRUNC('month', (ADD_MONTHS(DATE_ADD(DATE('{year}-{month}-{day}'), 1), -1)))  -- Gets the events truncated by the previous month start date
    GROUP BY 1, 11, 13, 14, 15, 16
),
final_m AS (
    SELECT
        m.reference_type,
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
),
checking_quarterly_snapshots AS (
    -- Checking if we have at least 83 snapshots of the previous quarter, since a quarter usually have around 90 days
    SELECT
        'LQ' AS reference_type,
        IF(COUNT(DISTINCT MAKE_DATE(year, month, day)) > 82, TRUE, FALSE) AS has_enough_snapshots
    FROM
        dw_rent_snapshot.rent_demand_events_snapshot
    WHERE
        MAKE_DATE(year, month, day)
            BETWEEN DATE_TRUNC('quarter', ADD_MONTHS(DATE_ADD(DATE('{year}-{month}-{day}'), 1), -3))
            AND DATE_TRUNC('quarter', DATE_ADD(DATE('{year}-{month}-{day}'), 1))
),
metrics_q AS (
    SELECT
        'LQ' AS reference_type,
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
        MAKE_DATE(year, month, day) AS dt_snapshot,
        country_code,
        year,
        month,
        day
    FROM
        dw_rent_snapshot.rent_demand_events_snapshot
    WHERE
        MAKE_DATE(year, month, day) = DATE_ADD(DATE('{year}-{month}-{day}'), 1)
        AND DATE_TRUNC('quarter', dt_event) = DATE_TRUNC('quarter', ADD_MONTHS(DATE_ADD(DATE('{year}-{month}-{day}'), 1), -3))  -- Gets the events truncated by the beginning of the previous quarter
    GROUP BY 1, 11, 13, 14, 15, 16
),
divergences_q AS (
    SELECT
        'LQ' AS reference_type,
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
        MAKE_DATE(year, month, day) AS dt_snapshot,
        country_code,
        year,
        month,
        day
    FROM
        dw_rent_snapshot.rent_demand_events_snapshot AS r
    JOIN
        checking_quarterly_snapshots AS c
            ON c.reference_type = 'LQ'
            AND c.has_enough_snapshots = TRUE
    WHERE
        MAKE_DATE(year, month, day) = DATE(DATE_TRUNC('quarter', DATE_ADD(DATE('{year}-{month}-{day}'), 1)))    -- Gets the snapshot of the first day of the next quarter (it'll have data of the whole previous quarter, til its last day)
        AND DATE(DATE_TRUNC('quarter', dt_event)) = DATE_TRUNC('quarter', (ADD_MONTHS(DATE_ADD(DATE('{year}-{month}-{day}'), 1), -3)))  -- Gets the events truncated by the previous quarter start date
    GROUP BY 1, 11, 13, 14, 15, 16
),
final_q AS (
    SELECT
        m.reference_type,
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
),
checking_yearly_snapshots AS (
    -- Checking if we have at least 340 snapshots of the previous year, since a year may have 365 or 366 days
    SELECT
        'LY' AS reference_type,
        IF(COUNT(DISTINCT MAKE_DATE(year, month, day)) > 339, TRUE, FALSE) AS has_enough_snapshots
    FROM
        dw_rent_snapshot.rent_demand_events_snapshot
    WHERE
        MAKE_DATE(year, month, day)
            BETWEEN DATE_TRUNC('year', ADD_MONTHS(DATE_ADD(DATE('{year}-{month}-{day}'), 1), -12))
            AND DATE_TRUNC('year', DATE_ADD(DATE('{year}-{month}-{day}'), 1))
),
metrics_y AS (
    SELECT
        'LY' AS reference_type,
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
        MAKE_DATE(year, month, day) AS dt_snapshot,
        country_code,
        year,
        month,
        day
    FROM
        dw_rent_snapshot.rent_demand_events_snapshot
    WHERE
        MAKE_DATE(year, month, day) = DATE_ADD(DATE('{year}-{month}-{day}'), 1)
        AND DATE_TRUNC('year', dt_event) = DATE_TRUNC('year', ADD_MONTHS(DATE_ADD(DATE('{year}-{month}-{day}'), 1), -12))   -- Gets the events truncated by the beginning of the previous year
    GROUP BY 1, 11, 13, 14, 15, 16
),
divergences_y AS (
    SELECT
        'LY' AS reference_type,
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
        MAKE_DATE(r.year, r.month, r.day) AS dt_snapshot,
        country_code,
        r.year,
        r.month,
        r.day
    FROM
        dw_rent_snapshot.rent_demand_events_snapshot AS r
    JOIN
        dw_public.dim_date AS d
            ON d.date = r.dt_event
    JOIN
        checking_yearly_snapshots AS c
            ON c.reference_type = 'LY'
            AND c.has_enough_snapshots = TRUE
    WHERE
        MAKE_DATE(r.year, r.month, r.day) = DATE(DATE_TRUNC('year', DATE_ADD(DATE('{year}-{month}-{day}'), 1)))   -- Gets the snapshot of the first day of the year (it'll have data of the whole previous year, til its last day)
        AND DATE(DATE_TRUNC('year', dt_event)) = MAKE_DATE(YEAR(d.last_year), 1, 1)   -- Gets the events truncated by the previous year start date
    GROUP BY 1, 11, 13, 14, 15, 16
),
final_y AS (
    SELECT
        m.reference_type,
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
)
SELECT
    reference_type,
    visits_booked,
    diff_vb,
    percentage_diff_vb,
    visits_completed,
    diff_vc,
    percentage_diff_vc,
    offers_submitted,
    diff_os,
    percentage_diff_os,
    offers_accepted,
    diff_oa,
    percentage_diff_oa,
    evaluation_started,
    diff_es,
    percentage_diff_es,
    evaluation_positive,
    diff_ep,
    percentage_diff_ep,
    documentation_sent,
    diff_ds,
    percentage_diff_ds,
    credit_approved,
    diff_ca,
    percentage_diff_ca,
    contracts_signed,
    diff_cs,
    percentage_diff_cs,
    dt_reference,
    dt_snapshot,
    country_code,
    year,
    month,
    day,
    NOW() AS ts_load
FROM
    metrics_d1
UNION ALL
SELECT
    reference_type,
    visits_booked,
    diff_vb,
    percentage_diff_vb,
    visits_completed,
    diff_vc,
    percentage_diff_vc,
    offers_submitted,
    diff_os,
    percentage_diff_os,
    offers_accepted,
    diff_oa,
    percentage_diff_oa,
    evaluation_started,
    diff_es,
    percentage_diff_es,
    evaluation_positive,
    diff_ep,
    percentage_diff_ep,
    documentation_sent,
    diff_ds,
    percentage_diff_ds,
    credit_approved,
    diff_ca,
    percentage_diff_ca,
    contracts_signed,
    diff_cs,
    percentage_diff_cs,
    dt_reference,
    dt_snapshot,
    country_code,
    year,
    month,
    day,
    NOW() AS ts_load
FROM
    final_5w
UNION ALL
SELECT
    reference_type,
    visits_booked,
    diff_vb,
    percentage_diff_vb,
    visits_completed,
    diff_vc,
    percentage_diff_vc,
    offers_submitted,
    diff_os,
    percentage_diff_os,
    offers_accepted,
    diff_oa,
    percentage_diff_oa,
    evaluation_started,
    diff_es,
    percentage_diff_es,
    evaluation_positive,
    diff_ep,
    percentage_diff_ep,
    documentation_sent,
    diff_ds,
    percentage_diff_ds,
    credit_approved,
    diff_ca,
    percentage_diff_ca,
    contracts_signed,
    diff_cs,
    percentage_diff_cs,
    dt_reference,
    dt_snapshot,
    country_code,
    year,
    month,
    day,
    NOW() AS ts_load
FROM
    final_m
UNION ALL
SELECT
    reference_type,
    visits_booked,
    diff_vb,
    percentage_diff_vb,
    visits_completed,
    diff_vc,
    percentage_diff_vc,
    offers_submitted,
    diff_os,
    percentage_diff_os,
    offers_accepted,
    diff_oa,
    percentage_diff_oa,
    evaluation_started,
    diff_es,
    percentage_diff_es,
    evaluation_positive,
    diff_ep,
    percentage_diff_ep,
    documentation_sent,
    diff_ds,
    percentage_diff_ds,
    credit_approved,
    diff_ca,
    percentage_diff_ca,
    contracts_signed,
    diff_cs,
    percentage_diff_cs,
    dt_reference,
    dt_snapshot,
    country_code,
    year,
    month,
    day,
    NOW() AS ts_load
FROM
    final_q
UNION ALL
SELECT
    reference_type,
    visits_booked,
    diff_vb,
    percentage_diff_vb,
    visits_completed,
    diff_vc,
    percentage_diff_vc,
    offers_submitted,
    diff_os,
    percentage_diff_os,
    offers_accepted,
    diff_oa,
    percentage_diff_oa,
    evaluation_started,
    diff_es,
    percentage_diff_es,
    evaluation_positive,
    diff_ep,
    percentage_diff_ep,
    documentation_sent,
    diff_ds,
    percentage_diff_ds,
    credit_approved,
    diff_ca,
    percentage_diff_ca,
    contracts_signed,
    diff_cs,
    percentage_diff_cs,
    dt_reference,
    dt_snapshot,
    country_code,
    year,
    month,
    day,
    NOW() AS ts_load
FROM
    final_y
