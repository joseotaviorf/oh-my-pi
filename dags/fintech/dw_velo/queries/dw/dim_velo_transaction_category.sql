SELECT
    id_category AS sk_category,
    description,
    nature_description,
    dre_description,
    NOW() AS ts_load
FROM
    datalake_velo.transaction_category
