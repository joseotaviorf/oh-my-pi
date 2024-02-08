SELECT DISTINCT
    d.id AS id_delinquency,
    d.id_propose,
    CASE
        WHEN id_type = 0 THEN 'SIGNATURE'
        WHEN id_type = 1 THEN 'GUARANTEE'
        WHEN id_type = 2 THEN 'TERMINATION'
        WHEN id_type = 3 THEN 'BILLING'
        WHEN id_type = 4 THEN 'RENEWAL'
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
    d.dt_paid,
    p.dt_ended AS dt_ended_propose,
    DATE(r.ts_created) AS dt_updated,
    DATE(d.ts_created) AS dt_created
FROM
    datalake_rental_guarantee_platform_clean.delinquency_aud AS d
LEFT JOIN
    datalake_rental_guarantee_platform_clean.rev_info AS r
    ON d.rev = r.rev
LEFT JOIN
    datalake_velo.propose AS p
        ON d.id_propose = p.id_propose
WHERE
    d.mod_amount_paid <> 0
    OR d.rev_type = 0
ORDER BY dt_updated, d.dt_due
