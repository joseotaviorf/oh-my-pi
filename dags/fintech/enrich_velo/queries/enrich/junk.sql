WITH cte_join AS (
    (
    SELECT
        'Origin' AS desc_master_type,
        id_origin AS id_lvl_1,
        origin_description AS desc_lvl_1

    FROM
        VALUES (1,'PJ/company'),
                (2,'PF') AS origin(id_origin, origin_description)
    )
    UNION ALL
    (
    SELECT
        'Propose Status' AS desc_master_type,
        id AS id_lvl_1,
        name AS desc_lvl_1
    FROM
        datalake_velo_clean.fiancavelo_proposestatus
    )
    UNION ALL
    (
    SELECT
        'Guarantee Status' AS desc_master_type,
        id AS id_lvl_1,
        name AS desc_lvl_1
    FROM
        datalake_velo_clean.fiancavelo_status
    )
    UNION ALL
    (
    SELECT
        'Propose Type' AS desc_master_type,
        id AS id_lvl_1,
        name AS desc_lvl_1
    FROM
        datalake_velo_clean.fiancavelo_proposetype
    )
    UNION ALL
    (
    SELECT
        'Billing Type' AS desc_master_type,
        id AS id_lvl_1,
        name AS desc_lvl_1
    FROM
        datalake_velo_clean.fiancavelo_billingtype
    )
    UNION ALL
    (
    SELECT
        'Payment Type' AS desc_master_type,
        id AS id_lvl_1,
        description AS desc_lvl_1

    FROM
        VALUES (1,'monthly'),
                (2,'annual'),
                (3, 'activation'),
                (4, 'collection/no info') AS origin(id, description)
    )
    UNION ALL
    (
    SELECT
        'Payment Status' AS desc_master_type,
        id AS id_lvl_1,
        name AS desc_lvl_1
    FROM
        datalake_velo_clean.fiancavelo_paymentstatus
    )
    UNION ALL
    (
    SELECT
        'Payment Gateway' AS desc_master_type,
        id AS id_lvl_1,
        name AS desc_lvl_1
    FROM
        datalake_velo_clean.fiancavelo_gateway
    )
),
cte_id_master_type AS (
    SELECT
        ROW_NUMBER() OVER( ORDER BY c.desc_master_type ASC) AS id_master_type,
        c.desc_master_type
    FROM
        cte_join AS c
    GROUP BY 2
)
SELECT
    ROW_NUMBER() OVER( ORDER BY cmt.id_master_type, c.id_lvl_1 ASC) AS id_junk,
    cmt.id_master_type,
    c.id_lvl_1,
    c.desc_master_type,
    c.desc_lvl_1
FROM
    cte_join AS c
LEFT JOIN
    cte_id_master_type AS cmt
    ON cmt.desc_master_type = c.desc_master_type
