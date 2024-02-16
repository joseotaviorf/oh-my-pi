WITH cte_base AS (
    SELECT DISTINCT
        d.id AS id_delinquency,
        d.id_propose,
        CASE
            WHEN d.id_type = 0 THEN 'SIGNATURE'
            WHEN d.id_type = 1 THEN 'GUARANTEE'
            WHEN d.id_type = 2 THEN 'TERMINATION'
            WHEN d.id_type = 3 THEN 'BILLING'
            WHEN d.id_type = 4 THEN 'RENEWAL'
            ELSE NULL
        END AS type_description,
        d.value AS delinquency_amount,
        d.original_value,
        d.amount_paid,
        d.value - d.amount_paid AS open_amount,
        d.value <= d.amount_paid AS is_finished,
        d.is_legacy_agreement,
        d.id_propose < 5000000 AS is_legacy_propose,
        d.dt_due,
        CASE
            WHEN d.dt_paid IS NOT NULL THEN d.dt_paid
            WHEN d.amount_paid > 0 AND d.dt_paid IS NULL AND del.dt_paid <= DATE(r.ts_created) AND (LAG(d.amount_paid) OVER (PARTITION BY d.id ORDER BY r.ts_created) <> d.amount_paid) THEN del.dt_paid
            WHEN d.amount_paid > 0 AND d.dt_paid IS NULL AND (LAG(d.amount_paid) OVER (PARTITION BY d.id ORDER BY r.ts_created) <> d.amount_paid) THEN DATE(r.ts_created)
            WHEN d.amount_paid > 0 AND d.dt_paid IS NULL AND (LAG(d.amount_paid) OVER (PARTITION BY d.id ORDER BY r.ts_created) = d.amount_paid) THEN NULL
            ELSE d.dt_paid
        END AS dt_paid,
        p.dt_ended AS dt_ended_propose,
        DATE(r.ts_created) AS dt_updated,
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
)

SELECT
    id_delinquency,
    id_propose,
    type_description,
    delinquency_amount,
    original_value,
    amount_paid,
    open_amount,
    is_finished,
    is_legacy_agreement,
    is_legacy_propose,
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
