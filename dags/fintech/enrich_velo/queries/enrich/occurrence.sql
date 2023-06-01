WITH cte_union AS (
(
    SELECT
        o.id AS id_occurrence,
        NULLIF(o.id_propose,0) AS id_propose,
        p.id AS id_payment,
        NULLIF(o.id_tenant, 0) AS id_client,
        jk1.id_junk AS id_occurrence_type,
        jk2.id_junk AS id_occurrence_status,
        o.unicid As id_unicid,
        NULLIF(TRIM(o.description), '') AS description,
        NULLIF(TRIM(o.invoice_url), '') AS invoice_url,
        o.value AS due_amount,
        o.original_value AS due_amount_original,
        o.paid_value AS paid_amount,
        o.is_valid,
        TRUE AS is_legacy,
        o.dt_due,
        IF(jk2.desc_lvl_1 = 'Finalizado' AND o.paid_value >= o.value,o.ts_updated,NULL) AS ts_paid,
        o.ts_inserted AS ts_created
    FROM
        datalake_velo_clean.fiancavelo_occurrence AS o
    LEFT JOIN
        datalake_velo_clean.fiancavelo_occurrencestatus AS os
            ON os.id = o.id_status
    LEFT JOIN
        datalake_velo_clean.fiancavelo_occurrencetype AS ot
            ON ot.id = o.id_type
    LEFT JOIN
        datalake_velo.junk AS jk1
            ON jk1.desc_lvl_1 = ot.name
            AND jk1.desc_master_type = 'Occurrence Type'
    LEFT JOIN
        datalake_velo.junk AS jk2
            ON jk2.desc_lvl_1 = os.name
            AND jk2.desc_master_type = 'Occurrence Status'
    LEFT JOIN
        datalake_velo_clean.fiancavelo_payment AS p
            ON TRIM(p.invoice_url) = TRIM(o.invoice_url)
            OR TRIM(p.unicid) = TRIM(o.unicid)
    WHERE
        o.is_active
    ORDER BY 1
)
UNION ALL
(
    WITH cte_payment AS (
        SELECT
                (ap.id + 5000000) * -1 AS id_payment,
                d.id AS id_occurrence
        FROM
            datalake_rental_guarantee_platform_clean.agreement_payment AS ap
        LEFT JOIN
            datalake_rental_guarantee_platform_clean.delinquency_has_agreement AS dha
            ON ap.id_agreement = dha.id_agreement
        LEFT JOIN
            datalake_rental_guarantee_platform_clean.delinquency AS d
            ON dha.id_delinquency = d.id
        QUALIFY
            ROW_NUMBER() OVER (PARTITION BY d.id ORDER BY ap.ts_updated ASC) = 1
        )
    SELECT
        o.id AS id_occurrence,
        o.id_propose,
        p.id_payment,
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
        FALSE AS is_legacy,
        o.dt_due,
        timestamp(o.dt_paid) AS ts_paid,
        o.ts_created
    FROM
        datalake_rental_guarantee_platform_clean.delinquency AS o
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.delinquency_has_agreement AS dha
        ON dha.id_delinquency = o.id
    LEFT JOIN
        cte_payment AS p
        ON p.id_occurrence = dha.id_delinquency
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
    WHERE o.id >= 5000000
)
ORDER BY 1
)
SELECT
    id_occurrence,
    id_propose,
    id_payment,
    id_client,
    id_occurrence_type,
    id_occurrence_status,
    id_unicid,
    description,
    invoice_url,
    due_amount,
    due_amount_original,
    paid_amount,
    is_valid,
    is_legacy,
    dt_due,
    ts_paid,
    ts_created
FROM
    cte_union
