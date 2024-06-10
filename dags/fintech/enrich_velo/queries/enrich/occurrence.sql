
WITH robin_hood AS (
    SELECT DISTINCT
        SPLIT(ae.id_external, ':')[1] AS id_occurrence,
        ARRAY_AGG(ae.id) AS ids_accounting_entry
        -- SPLIT(ae.id_external, ':')[0] AS id_propose
    FROM
        datalake_robin_hood.accounting_entry AS ae
    INNER JOIN
        datalake_robin_hood_raw.accounting_entry_source AS aes
            ON aes.id = ae.id_source
    WHERE
        aes.name LIKE 'Fiador profissional:%'
    GROUP BY 1
)

SELECT DISTINCT
    o.id AS id_occurrence,
    o.id_propose,
    CAST(NULL AS BIGINT) AS id_client,
    jk1.id_junk AS id_occurrence_type,
    jk2.id_junk AS id_occurrence_status,
    CAST(NULL AS STRING) AS id_unicid,
    rh.ids_accounting_entry,
    CAST(NULL AS STRING) AS description,
    CAST(NULL AS STRING) AS invoice_url,
    o.value AS due_amount,
    o.original_value AS due_amount_original,
    o.amount_paid AS paid_amount,
    IF(o.id_status IN (3,7) AND o.amount_paid < o.original_value, o.original_value - o.amount_paid, NULL) AS discount_amount,
    o.is_valid,
    o.id > 15 AND o.id < 5000000 AS is_legacy,
    IF(o.id > 15 AND o.id < 5000000, o.dt_due, CAST(NULL AS DATE)) AS dt_due_legacy,
    IF(o.id > 5000000, o.dt_due, CAST(NULL AS DATE)) AS dt_due,
    dt_bill_month,
    dt_payment_scheduled,
    timestamp(o.dt_paid) AS ts_paid,
    o.ts_created
FROM
    datalake_rental_guarantee_platform_clean.delinquency AS o
LEFT JOIN
    datalake_rental_guarantee_platform_clean.delinquency_has_agreement AS dha
    ON dha.id_delinquency = o.id
LEFT JOIN
    robin_hood AS rh
    ON o.id = rh.id_occurrence
LEFT JOIN
    datalake_velo.junk AS jk1
        ON jk1.desc_lvl_1 = CASE
                                WHEN o.id_type = 0 THEN 'SIGNATURE'
                                WHEN o.id_type = 1 THEN 'GUARANTEE'
                                WHEN o.id_type = 2 THEN 'TERMINATION'
                                WHEN o.id_type = 3 THEN 'BILLING'
                                WHEN o.id_type = 4 THEN 'RENEWAL'
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
                                WHEN o.id_status = 6 THEN 'ACTIVE_FALSE'
                                WHEN o.id_status = 7 THEN 'FORGIVEN'
                                ELSE NULL
                            END
        AND jk2.desc_master_type = 'Occurrence Status'
WHERE
   is_active = True

UNION ALL
-- The following query is a complement for delinquancy table, it adds all cpfs from 2.0 that are not linked to any contract (this cases are going to be resolved manually, so when one case is fixed, it will be added to 3.0 and remove from this table).
SELECT DISTINCT
    ol.id * -1 AS id_occurrence,
    ol.propose AS id_propose,
    CAST(NULL AS BIGINT) AS id_client,
    jk1.id_junk AS id_occurrence_type,
    CAST(NULL AS INTEGER) AS id_occurrence_status,
    CAST(NULL AS STRING) AS id_unicid,
    CAST(NULL AS ARRAY<INT>) AS ids_accounting_entry,
    CAST(NULL AS STRING) AS description,
    CAST(NULL AS STRING) AS invoice_url,
    ol.value AS due_amount,
    CAST(NULL AS DECIMAL(10,2)) AS due_amount_original,
    ol.paid_value AS paid_amount,
    CAST(NULL AS DECIMAL(10,2)) AS discount_amount,
    CAST(NULL AS BOOLEAN) AS is_valid,
    True AS is_legacy,
    ol.ts_due AS dt_due_legacy,
    CAST(NULL AS DATE) AS dt_due,
    CAST(NULL AS DATE) AS dt_bill_month,
    CAST(NULL AS DATE) AS dt_payment_scheduled,
    CAST(NULL AS TIMESTAMP) AS ts_paid,
    CAST(NULL AS TIMESTAMP) AS ts_created
FROM
    datalake_rental_guarantee_platform_clean.omie_occurrence_legacy ol
LEFT JOIN
    datalake_velo.junk AS jk1
        ON jk1.desc_lvl_1 = CASE
                                WHEN ol.type = 'Assinatura' THEN 'SIGNATURE'
                                WHEN ol.type = 'Garantia' THEN 'GUARANTEE'
                                WHEN ol.type = 'Rescisao' THEN 'TERMINATION'
                                ELSE NULL
                            END
        AND jk1.desc_master_type = 'Occurrence Type'
