WITH
  cte_base AS (
    SELECT DISTINCT
        d.id AS id_delinquency,
        del.id_propose,
        del.id_type,
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
        IF(d.amount_paid > 0 AND (LAG(d.amount_paid) OVER (PARTITION BY d.id ORDER BY COALESCE(r.ts_created, d.dt_paid)) <> d.amount_paid) , d.amount_paid - LAG(d.amount_paid) OVER (PARTITION BY d.id ORDER BY COALESCE(r.ts_created, d.dt_paid)), 0) AS amount_paid_added,
        d.value <= d.amount_paid AS is_finished,
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
        OR d.rev_type = 0)
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
        dt_updated_arq,
        MIN(dt_updated) AS dt_updated,
        dt_created
    FROM
        cte_final
    GROUP BY 1,2,3,4,5,6,7,9,10,11,12,13,14,15,16,17,19
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
        CASE
            WHEN t.id_type IN (0,4,5) AND DATE(t.dt_created) >= DATE("2024-02-01") THEN t.dt_due
            WHEN t.id_delinquency < 15 OR t.id_delinquency >= 5000000 THEN DATE(t.dt_created)
            ELSE t.dt_due
        END AS dt_fatura,
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
        t.dt_updated_arq,
        MAX(t.dt_updated_paid) AS dt_updated
    FROM
        datalake_quintoandar.aux_date AS d
    LEFT JOIN
        timeline_base AS t
            ON IF(t.is_finished, d.`date` >= t.dt_updated_paid AND d.`date` <= LAST_DAY(t.dt_updated_paid), IF(t.is_currently_active = true, d.`date` >= t.dt_fatura AND (d.`date` <= t.dt_delinquency_last_register OR t.dt_delinquency_last_register IS NULL), d.`date` >= IF(t.dt_created > t.dt_due, t.dt_due, t.dt_created) AND d.`date` <= t.dt_delinquency_last_register))
    WHERE
        d.`date` > DATE('2020-01-01')
        AND d.`date` <= CURRENT_DATE()
    GROUP BY 1,2,3,4
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
            AND COALESCE(td.dt_updated,t.dt_updated_arq) = COALESCE(t.dt_paid, t.dt_updated, t.dt_updated_arq)
),
cte_timeline_status AS (
    WITH base_cte_status AS (
        WITH base_fix AS (
        SELECT
            a.id,
            a.id_propose,
            LAST_VALUE(a.id_status) AS id_status,
            r.ts_created,
            a.dt_payment_scheduled,
            DATEADD(HOUR, -3, r.ts_created) AS ts_created_local,
            a.dt_due,
            a.rev,
            a.rev_end,
            CASE
                WHEN a.id_type IN (0,4,5) AND DATE(a.ts_created) >= DATE("2024-02-01") THEN a.dt_due
                WHEN a.id < 15 OR a.id >= 5000000 THEN DATE(a.ts_created)
                ELSE a.dt_due
            END AS dt_fatura,
            re.ts_created AS ts_ended,
            IF(re.ts_created IS NULL AND a.id_status = 3, LAST_DAY(r.ts_created), re.ts_created) AS ts_ended_3
        FROM
            datalake_rental_guarantee_platform_clean.delinquency_aud a
        LEFT JOIN
            datalake_rental_guarantee_platform_clean.rev_info r
            ON a.rev = r.rev
        LEFT JOIN
            datalake_rental_guarantee_platform_clean.rev_info re
            ON a.rev_end = re.rev
            AND NOT a.mod_id_propose <=> TRUE
        GROUP BY 1,2,4,5,6,7,8,9,10,11,12
        QUALIFY
            ROW_NUMBER() OVER(PARTITION BY a.id, DATE(r.ts_created) ORDER BY r.ts_created DESC) = 1
        )
        SELECT
            *,
            IF(rev_end IS NOT NULL AND ts_ended IS NULL, LAG(ts_created_local) OVER (PARTITION BY id ORDER BY ts_created_local DESC),ts_ended) AS ts_ended_fixed
        FROM base_fix
    )
    SELECT
        s.id,
        s.id_status AS id_status,
        d.date AS dt_status_updated
    FROM
        datalake_quintoandar.aux_date AS d
    LEFT JOIN
        base_cte_status s
        ON IF( s.ts_ended_fixed IS NOT NULL OR s.ts_ended_3 IS NOT NULL, d.`date` >= s.dt_fatura AND IF(s.ts_ended_fixed IS NOT NULL, d.`date` < DATE(s.ts_ended_fixed), d.`date` <= DATE(s.ts_ended_3)), d.`date` >= IF(DATE(s.dt_payment_scheduled) < DATE(s.ts_created_local), DATE(s.dt_payment_scheduled), DATE(s.ts_created_local)))
    WHERE
        d.`date` > DATE('2020-01-01')
        AND d.`date` <= CURRENT_DATE()
)
SELECT
    t.id_delinquency,
    t.id_propose,
    t.type_description,
    MIN(s.id_status) AS id_status,
    MAX(t.delinquency_amount) AS delinquency_amount,
    MAX(t.original_value) AS original_value,
    MAX(t.amount_paid) AS amount_paid,
    MAX(t.amount_paid_added_fixed) AS amount_paid_added,
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
    MIN(t.dt_created) AS dt_created
FROM
    timeline AS t
LEFT JOIN
    cte_timeline_status s
    ON t.id_delinquency = s.id
    AND DATE(t.`date`) = DATE(s.dt_status_updated)
WHERE
    s.id_status IS NOT NULL
    AND t.date >= ADD_MONTHS(CURRENT_DATE, -6)
GROUP BY 1,2,3,17
