WITH
cte_base AS (
    SELECT DISTINCT
        d.id AS id_delinquency,
        del.id_propose,
        del.id_type,
        CASE
            WHEN del.id_type IN (0, 6) THEN 'SIGNATURE'
            WHEN del.id_type = 1 THEN 'GUARANTEE'
            WHEN del.id_type = 2 THEN 'TERMINATION'
            WHEN del.id_type = 3 THEN 'BILLING'
            WHEN del.id_type IN (4, 5) THEN 'RENEWAL'
            ELSE NULL
        END AS type_description,
        del.value AS delinquency_amount,
        del.original_value,
        d.amount_paid,
        d.value - d.amount_paid AS open_amount,
        IF(d.amount_paid > 0 AND (LAG(d.amount_paid) OVER (PARTITION BY d.id ORDER BY COALESCE(r.ts_created, d.dt_paid)) <> d.amount_paid) , d.amount_paid - LAG(d.amount_paid) OVER (PARTITION BY d.id ORDER BY COALESCE(r.ts_created, d.dt_paid)), 0) AS amount_paid_added,
        IF(d.value <= d.amount_paid OR (d.id_status = 3 AND d.rev_end IS NULL), true, false) AS is_finished,
        del.is_legacy_agreement,
        del.id_propose < 5000000 AS is_legacy_propose,
        del.is_active AS is_currently_active,
        d.dt_due,
        CASE
            WHEN d.dt_paid IS NOT NULL THEN d.dt_paid
            WHEN d.amount_paid > 0 AND d.dt_paid IS NULL AND del.dt_paid <= DATE(r.ts_created) AND (LAG(d.amount_paid) OVER (PARTITION BY d.id ORDER BY r.ts_created) <> d.amount_paid) THEN del.dt_paid
            WHEN d.amount_paid > 0 AND d.dt_paid IS NULL AND (LAG(d.amount_paid) OVER (PARTITION BY d.id ORDER BY r.ts_created) <> d.amount_paid) THEN DATE(r.ts_created)
            WHEN d.amount_paid > 0 AND d.dt_paid IS NULL AND (LAG(d.amount_paid) OVER (PARTITION BY d.id ORDER BY r.ts_created) = d.amount_paid) THEN NULL
            ELSE d.dt_paid
        END AS dt_paid,
        p.dt_ended AS dt_ended_propose,
        DATE(COALESCE(DATEADD(HOUR, -3, r.ts_created), d.dt_paid)) AS dt_updated,
        IF(is_currently_active, DATE(COALESCE(r.ts_created, d.dt_paid)),DATE(del.ts_updated)) AS dt_updated_arq,
        IF(DATE(del.dt_payment_scheduled) < DATE(del.ts_created), DATE(del.dt_payment_scheduled), DATE(del.ts_created)) AS dt_created,
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
        (d.mod_amount_paid <> 0
        OR d.rev_type IN (0,1))
),
cte_final AS (
    SELECT
        id_delinquency,
        id_propose,
        id_type,
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
        dt_updated_arq,
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
        id_type,
        type_description,
        delinquency_amount,
        original_value,
        MAX(amount_paid_added) AS amount_paid_added,
        open_amount,
        is_finished,
        is_legacy_agreement,
        is_legacy_propose,
        is_currently_active,
        dt_due,
        dt_paid,
        dt_ended_propose,
        dt_updated_arq,
        MIN(dt_updated) AS dt_updated,
        dt_created
    FROM
        cte_final
    GROUP BY 1,2,3,4,5,6,8,9,10,11,12,13,14,15,16,18
),
delinquency_end AS (
    SELECT DISTINCT
        id_delinquency,
        IF(is_currently_active, COALESCE(dt_paid, dt_updated), dt_updated_arq) AS dt_updated
    FROM
        base_timeline
    WHERE
        (is_finished
        OR is_currently_active = false)
),
timeline_base AS (
    SELECT
        t.*,
        COALESCE(t.dt_paid, t.dt_updated) AS dt_updated_paid,
        DATE(t.dt_created) AS dt_fatura,
        CASE
            WHEN t.id_delinquency < 5000000 THEN DATE(t.dt_due)
            WHEN t.id_type IN (0, 4, 5, 6) THEN DATE(t.dt_due)
            ELSE DATE(t.dt_created)
        END AS dt_aging,
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
        IF(t.dt_paid IS NULL, t.dt_updated_arq, t.dt_paid) AS dt_updated_arq,
        MAX(t.dt_updated_paid) AS dt_updated,
        MIN(dt_aging) AS dt_aging
    FROM
        datalake_quintoandar.aux_date AS d
    LEFT JOIN
        timeline_base AS t
            ON IF(t.is_finished, d.`date` >= t.dt_updated_paid AND d.`date` <= LAST_DAY(t.dt_updated_paid), IF(t.is_currently_active = true, d.`date` >= t.dt_fatura AND (d.`date` <= LAST_DAY(t.dt_delinquency_last_register) OR t.dt_delinquency_last_register IS NULL), d.`date` >= t.dt_fatura AND d.`date` <= LAST_DAY(t.dt_delinquency_last_register)))
    WHERE
        d.`date` > DATE('2020-01-01')
        AND d.`date` <= CURRENT_DATE()
    GROUP BY 1,2,3,4
),
timeline AS (
    SELECT
        td.`date`,
        td.dt_aging,
        t.*
        -- IF(td.`date` <= COALESCE(t.dt_paid, t.dt_updated), 0.00, t.amount_paid_added) AS amount_paid_added_fixed
    FROM
        cte_timeline_daily AS td
    LEFT JOIN
        base_timeline AS t
            ON td.id_delinquency = t.id_delinquency
            AND COALESCE(td.dt_updated,t.dt_updated_arq) = COALESCE(t.dt_paid, t.dt_updated, t.dt_updated_arq)
),
payment_evol AS (
    SELECT DISTINCT
        t.`date`,
        t.id_delinquency,
        SUM(IF(t.dt_paid = t.`date`, t.amount_paid_added,0)) AS amount_paid_added,
        SUM(IF(t.dt_paid <= t.`date` AND DATE_TRUNC('MONTH', t.dt_paid) = DATE_TRUNC('MONTH', t.`date`), t.amount_paid_added,0)) AS amount_paid_added_month,
        SUM(IF(t.dt_paid <= t.`date`, t.amount_paid_added,0)) AS amount_paid_added_accrual
    FROM
        timeline AS t
    GROUP BY
        1, 2
)
SELECT
    t.id_delinquency,
    t.id_propose,
    t.type_description,
    MIN(s.id_status) AS id_status,
    MAX(t.delinquency_amount) AS delinquency_amount,
    MAX(t.original_value) AS original_value,
    MAX(p.amount_paid_added) AS amount_paid_added,
    MAX(p.amount_paid_added_month) AS amount_paid_added_month,
    MAX(p.amount_paid_added_accrual) AS amount_paid_added_accrual,
    MIN(t.open_amount) AS open_amount,
    MIN(t.delinquency_amount - p.amount_paid_added_accrual) AS open_amount_deducted,
    FIRST_VALUE(MIN(t.delinquency_amount - p.amount_paid_added_accrual)) OVER (PARTITION BY t.id_delinquency, YEAR(t.`date`), MONTH(t.`date`) ORDER BY t.`date`) AS open_amount_first_day_of_month,
    MAX(t.is_finished) As is_finished,
    MAX(t.is_legacy_agreement) AS is_legacy_agreement,
    MAX(t.is_legacy_propose) AS is_legacy_propose,
    MAX(t.is_currently_active) AS is_currently_active,
    MAX(IF(t.dt_updated_arq > t.`date`, FALSE, TRUE)) AS is_active_timeline,
    MAX(t.dt_due) AS dt_due,
    MAX(t.dt_ended_propose) AS dt_ended_propose,
    t.`date` AS dt_base,
    t.dt_aging,
    MAX(IF(t.dt_paid <= t.`date`, t.dt_paid, NULL)) AS dt_paid,
    MIN(t.dt_created) AS dt_created
FROM
    timeline AS t
LEFT JOIN
    datalake_collections_quintocred.status_timeline s
    ON t.id_delinquency = s.id
    AND DATE(t.`date`) = DATE(s.dt_status_updated)
LEFT JOIN
    payment_evol p
    ON t.id_delinquency = p.id_delinquency
    AND DATE(t.`date`) = DATE(p.`date`)
WHERE
    s.id_status IS NOT NULL
GROUP BY 1,2,3,20,21
