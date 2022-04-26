SELECT
    s.id AS id_sale,
    s.id_external_offer,
    o.id_outcome,
    o.dt_occurence,
    s.ts_created
FROM
    datalake_monopoly_clean.sale s
LEFT JOIN
    datalake_monopoly_clean.outcome_status_log o
        ON o.id = s.id