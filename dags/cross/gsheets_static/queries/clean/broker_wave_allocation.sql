SELECT
    CAST(NULLIF(REPLACE(sk_broker, ',', ''), '') AS INT) AS sk_broker,
    CAST(NULLIF(REPLACE(qtd_contratos, ',', ''), '') AS INT) AS qtd_contratos,
    CAST(NULLIF(REPLACE(expected_revenue, ',', ''), '') AS DECIMAL(14,2)) AS expected_revenue,
    CAST(NULLIF(REPLACE(share_contratos, ',', ''), '') AS DECIMAL(14,10)) AS share_contratos,
    CAST(NULLIF(REPLACE(contratos_acc, ',', ''), '') AS INT) AS contratos_acc,
    CAST(NULLIF(REPLACE(share_contratos_acc, ',', ''), '') AS DECIMAL(14,10)) AS share_contratos_acc,
    CAST(NULLIF(REPLACE(rank, ',', ''), '') AS INT) AS rank,
    CAST(NULLIF(REPLACE(share_reas, ',', ''), '') AS DECIMAL(14,10)) AS share_reas,
    wave
FROM
    datalake_gsheets_raw.nexxera_holly_days
