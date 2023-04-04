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
    o.dt_due,
    IF(jk2.desc_lvl_1 = 'Finalizado' AND o.paid_value >= o.value,o.ts_updated,NULL) AS ts_paid,
    o.ts_inserted AS ts_created
FROM
    datalake_velo_clean.fiancavelo_occurrence AS o
LEFT JOIN
    datalake_velo.junk AS jk1
        ON jk1.id_lvl_1 = o.id_type
        AND jk1.desc_master_type = 'Occurrence Type'
LEFT JOIN
    datalake_velo.junk AS jk2
        ON jk2.id_lvl_1 = o.id_status
        AND jk2.desc_master_type = 'Occurrence Status'
LEFT JOIN
    datalake_velo_clean.fiancavelo_payment AS p
        ON TRIM(p.invoice_url) = TRIM(o.invoice_url)
        OR TRIM(p.unicid) = TRIM(o.unicid)
WHERE
    o.is_active
ORDER BY 1
