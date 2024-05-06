WITH cte_explode AS (
    SELECT
        EXPLODE(
            ARRAY(
                'ACORDO',
                'CONDOMINIO',
                'MULTA-RECISORIA',
                'MULTAS ONGOING',
                'RENTAL-CORE',
                'REPAROS',
                'UTILIDADES'
            )
        ) AS desc_lvl_1,
        'bill_item_cluster_name' AS desc_master_type
    UNION ALL
    SELECT
        EXPLODE(
            ARRAY(
                'CANCELADA',
                'PAGA',
                'A VENCER',
                'VENCIDA'
            )
        ) AS desc_lvl_1,
        'invoice_temporal_status' AS desc_master_type
),

cte_create_id AS (
    SELECT
        desc_master_type,
        desc_lvl_1,
        ROW_NUMBER() OVER(PARTITION BY desc_master_type ORDER BY desc_master_type) AS id_lvl_1
    FROM cte_explode
),

cte_id_master_type AS (
    SELECT
        ROW_NUMBER() OVER( ORDER BY c.desc_master_type ASC) AS id_master_type,
        c.desc_master_type
    FROM
        cte_create_id AS c
    GROUP BY 2
)
SELECT
    ROW_NUMBER() OVER( ORDER BY cmt.id_master_type, c.id_lvl_1 ASC) AS id_junk,
    cmt.id_master_type,
    c.id_lvl_1,
    c.desc_master_type,
    c.desc_lvl_1
FROM
    cte_create_id AS c
LEFT JOIN
    cte_id_master_type AS cmt
    ON cmt.desc_master_type = c.desc_master_type
