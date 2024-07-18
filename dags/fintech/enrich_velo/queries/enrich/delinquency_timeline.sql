WITH cte_base AS (
    SELECT DISTINCT
        d.id AS id_delinquency,
        del.id_propose,
        CASE
            WHEN del.id_type = 0 THEN 'SIGNATURE'
            WHEN del.id_type = 1 THEN 'GUARANTEE'
            WHEN del.id_type = 2 THEN 'TERMINATION'
            WHEN del.id_type = 3 THEN 'BILLING'
            WHEN del.id_type = 4 THEN 'RENEWAL'
            ELSE NULL
        END AS type_description,
        del.value AS delinquency_amount,
        del.original_value,
        d.amount_paid,
        d.value - d.amount_paid AS open_amount,
        IF( d.amount_paid > 0 AND (LAG(d.amount_paid) OVER (PARTITION BY d.id ORDER BY COALESCE(r.ts_created, d.dt_paid)) <> d.amount_paid) , d.amount_paid - LAG(d.amount_paid) OVER (PARTITION BY d.id ORDER BY COALESCE(r.ts_created, d.dt_paid)) , 0) AS amount_paid_added,
        d.value <= d.amount_paid AS is_finished,
        del.is_legacy_agreement,
        del.id_propose < 5000000 AS is_legacy_propose,
        d.is_active AS is_currently_active,
        d.dt_due,
        CASE
            WHEN d.dt_paid IS NOT NULL THEN d.dt_paid
            WHEN d.amount_paid > 0 AND d.dt_paid IS NULL AND del.dt_paid <= DATE(r.ts_created) AND (LAG(d.amount_paid) OVER (PARTITION BY d.id ORDER BY r.ts_created) <> d.amount_paid) THEN del.dt_paid
            WHEN d.amount_paid > 0 AND d.dt_paid IS NULL AND (LAG(d.amount_paid) OVER (PARTITION BY d.id ORDER BY r.ts_created) <> d.amount_paid) THEN DATE(r.ts_created)
            WHEN d.amount_paid > 0 AND d.dt_paid IS NULL AND (LAG(d.amount_paid) OVER (PARTITION BY d.id ORDER BY r.ts_created) = d.amount_paid) THEN NULL
            ELSE d.dt_paid
        END AS dt_paid,
        p.dt_ended AS dt_ended_propose,
        DATE(COALESCE(r.ts_created, d.dt_paid)) AS dt_updated,
        DATE(del.ts_created) AS dt_created,
        ROW_NUMBER() OVER (PARTITION BY d.id ORDER BY DATE(COALESCE(r.ts_created, d.dt_paid)) ASC) AS rn
    FROM
        datalake_rental_guarantee_platform_clean.delinquency_aud AS d
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.rev_info AS r
            ON d.rev = r.rev
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.delinquency AS del
            ON d.id = del.id
    LEFT JOIN
        datalake_velo.propose AS p
            ON d.id_propose = p.id_propose
    WHERE
        d.mod_amount_paid <> 0
        OR d.rev_type = 0
),
cte_final AS (
    SELECT
        id_delinquency,
        id_propose,
        type_description,
        delinquency_amount,
        original_value,
        amount_paid,
        amount_paid_added,
        open_amount,
        is_finished,
        is_legacy_agreement,
        is_legacy_propose,
        is_currently_active,
        dt_due,
        CASE
            WHEN amount_paid > 0 AND dt_paid IS NULL AND (LAG(amount_paid) OVER (PARTITION BY id_delinquency ORDER BY dt_updated) = amount_paid) THEN LAG(dt_paid) IGNORE NULLS OVER (PARTITION BY id_delinquency ORDER BY dt_updated)
            ELSE dt_paid
        END AS dt_paid,
        dt_ended_propose,
        dt_updated,
        dt_created
    FROM
        cte_base
    WHERE
        (
            amount_paid = 0
            OR amount_paid_added > 0
        )
        OR rn = 1
),
base_timeline AS (
    SELECT
        id_delinquency,
        id_propose,
        type_description,
        delinquency_amount,
        original_value,
        amount_paid,
        MAX(amount_paid_added) AS amount_paid_added,
        open_amount,
        is_finished,
        is_legacy_agreement,
        is_legacy_propose,
        is_currently_active,
        dt_due,
        dt_paid,
        dt_ended_propose,
        MIN(dt_updated) AS dt_updated,
        dt_created
    FROM
        cte_final
    GROUP BY 1,2,3,4,5,6,8,9,10,11,12,13,14,15,17
),
delinquency_end AS (
    SELECT DISTINCT
        id_delinquency,
        COALESCE(dt_paid, dt_updated) AS dt_updated
    FROM
        base_timeline
    WHERE
        is_finished
),
timeline_base AS (
    SELECT
        t.*,
        COALESCE(t.dt_paid, t.dt_updated) AS dt_updated_paid,
        de.dt_updated AS dt_delinquency_last_register
    FROM
        base_timeline AS t
    LEFT JOIN
        delinquency_end de
            ON de.id_delinquency = t.id_delinquency
),
cte_timeline_daily AS (
    SELECT
        d.`date`,
        d.month_start,
        t.id_delinquency,
        MAX(t.dt_updated_paid) AS dt_updated
    FROM
        datalake_quintoandar.aux_date AS d
    LEFT JOIN
        timeline_base AS t
            ON IF(t.is_finished, d.`date` >= t.dt_updated_paid AND d.`date` <= LAST_DAY(t.dt_updated_paid), d.`date` >= t.dt_updated_paid AND d.`date` < t.dt_delinquency_last_register)
    WHERE
        d.`date` > DATE('2020-01-01')
        AND d.`date` < CURRENT_DATE()
    GROUP BY 1,2,3
    ORDER BY 3,1
),
timeline AS (
    SELECT
        td.`date`,
        t.*,
        IF(td.`date` <> COALESCE(t.dt_paid, t.dt_updated), 0.00, t.amount_paid_added) AS amount_paid_added_fixed
    FROM
        cte_timeline_daily AS td
    LEFT JOIN
        base_timeline AS t
            ON td.id_delinquency = t.id_delinquency
            AND td.dt_updated = COALESCE(t.dt_paid, t.dt_updated)
),
cte_timeline_status AS (
    WITH base_cte_status AS (
        SELECT
            a.id,
            LAST_VALUE(a.id_status) AS id_status,
            DATE(r.ts_created)
        FROM
            datalake_rental_guarantee_platform_clean.delinquency_aud a
        LEFT JOIN
            datalake_rental_guarantee_platform_clean.rev_info r
            ON a.rev = r.rev
        WHERE a.mod_id_status = true
        GROUP BY 1,3
        )
    SELECT
        s.id,
        LAST_VALUE(s.id_status) AS id_status,
        d.date AS dt_status_updated
    FROM
        datalake_quintoandar.aux_date AS d
    LEFT JOIN
        base_cte_status s
        ON d.`date` >= DATE(s.ts_created)
    WHERE
        d.`date` > DATE('2020-01-01')
        AND d.`date` < CURRENT_DATE()
    GROUP BY 1,3
)
SELECT
    t.id_delinquency,
    t.id_propose,
    t.type_description,
    MIN(s.id_status) AS id_status,
    MAX(t.delinquency_amount) AS delinquency_amount,
    MAX(t.original_value) AS original_value,
    MAX(t.amount_paid) AS amount_paid,
    SUM(t.amount_paid_added_fixed) AS amount_paid_added,
    MIN(t.open_amount) AS open_amount,
    FIRST_VALUE(MIN(t.open_amount)) OVER (PARTITION BY t.id_delinquency, YEAR(t.`date`), MONTH(t.`date`) ORDER BY t.`date`) AS open_amount_first_day_of_month,
    MAX(t.is_finished) As is_finished,
    MAX(t.is_legacy_agreement) AS is_legacy_agreement,
    MAX(t.is_legacy_propose) AS is_legacy_propose,
    MAX(t.is_currently_active) AS is_currently_active,
    MAX(t.dt_due) AS dt_due,
    MAX(t.dt_ended_propose) AS dt_ended_propose,
    t.`date` AS dt_base,
    MAX(t.dt_paid) AS dt_paid,
    MAX(t.dt_created) AS dt_created
FROM
    timeline AS t
LEFT JOIN
    cte_timeline_status s
    ON t.id_delinquency = s.id
    AND t.`date` = DATE(s.dt_status_updated)
GROUP BY 1,2,3,17
