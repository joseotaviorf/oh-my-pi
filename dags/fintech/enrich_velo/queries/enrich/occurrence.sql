
SELECT DISTINCT
    o.id AS id_occurrence,
    o.id_propose,
    NULL AS id_client,
    jk1.id_junk AS id_occurrence_type,
    jk2.id_junk AS id_occurrence_status,
    NULL AS id_unicid,
    NULL AS description,
    NULL AS invoice_url,
    o.value AS due_amount,
    o.original_value AS due_amount_original,
    o.amount_paid AS paid_amount,
    o.is_valid,
    o.id > 15 AND o.id <= 5000000 AS is_legacy,
    o.dt_due,
    timestamp(o.dt_paid) AS ts_paid,
    o.ts_created
FROM
    datalake_rental_guarantee_platform_clean.delinquency AS o
LEFT JOIN
    datalake_rental_guarantee_platform_clean.delinquency_has_agreement AS dha
    ON dha.id_delinquency = o.id
LEFT JOIN
    datalake_velo.junk AS jk1
        ON jk1.desc_lvl_1 = CASE
                                WHEN o.id_type = 0 THEN 'SIGNATURE'
                                WHEN o.id_type = 1 THEN 'GUARANTEE'
                                WHEN o.id_type = 2 THEN 'TERMINATION'
                                WHEN o.id_type = 3 THEN 'BILLING'
                                ELSE NULL
                            END
        AND jk1.desc_master_type = 'Occurrence Type'
LEFT JOIN
    datalake_velo.junk AS jk2
        ON jk2.desc_lvl_1 = CASE
                                WHEN o.id_status = 0 THEN 'REGISTERED'
                                WHEN o.id_status = 1 THEN 'RECOVERING'
                                WHEN o.id_status = 2 THEN 'PROGRESS'
                                WHEN o.id_status = 3 THEN 'FINISHED'
                                WHEN o.id_status = 4 THEN 'UNDER_AGREEMENT'
                                WHEN o.id_status = 5 THEN 'REQUESTED_AGREEMENT'
                                ELSE NULL
                            END
        AND jk2.desc_master_type = 'Occurrence Status'
