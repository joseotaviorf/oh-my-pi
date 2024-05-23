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
        DATE(COALESCE(r.ts_created, d.dt_paid)) AS dt_updated,
        DATE(del.ts_created) AS dt_created
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
)

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
