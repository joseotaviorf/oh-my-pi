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
        WITH cte_prop_status AS (
            SELECT
                name AS desc_lvl_1
                FROM
                    datalake_rental_guarantee_platform_clean.propose_status
            )
        SELECT
            'Propose Status' AS desc_master_type,
            ROW_NUMBER() OVER( ORDER BY desc_lvl_1 ASC) AS id_lvl_1,
            desc_lvl_1
        FROM
            cte_prop_status
        GROUP BY desc_lvl_1
    )
    UNION ALL
    (
        WITH cte_guar_status AS (
            SELECT
                name AS desc_lvl_1
                FROM
                    datalake_rental_guarantee_platform_clean.contract_status
            )
        SELECT
            'Guarantee Status' AS desc_master_type,
            ROW_NUMBER() OVER( ORDER BY desc_lvl_1 ASC) AS id_lvl_1,
            desc_lvl_1
        FROM
            cte_guar_status
        GROUP BY desc_lvl_1
    )
    UNION ALL
    (
        WITH cte_prop_type AS (
            SELECT
                name AS desc_lvl_1
                FROM
                    datalake_rental_guarantee_platform_clean.bussines_type
            )
        SELECT
            'Propose Type' AS desc_master_type,
            ROW_NUMBER() OVER( ORDER BY desc_lvl_1 ASC) AS id_lvl_1,
            desc_lvl_1
        FROM
            cte_prop_type
        GROUP BY desc_lvl_1
    )
    UNION ALL
    (
        WITH cte_billing_type AS (
            SELECT
                name AS desc_lvl_1
                FROM
                    datalake_velo_clean.fiancavelo_billingtype
            WHERE name NOT IN (SELECT DISTINCT billing_type FROM datalake_rental_guarantee_platform_clean.payment)
            UNION ALL
            SELECT
                DISTINCT billing_type AS desc_lvl_1
            FROM
                datalake_rental_guarantee_platform_clean.payment
            )
        SELECT
            'Billing Type' AS desc_master_type,
            ROW_NUMBER() OVER( ORDER BY desc_lvl_1 ASC) AS id_lvl_1,
            desc_lvl_1
        FROM
            cte_billing_type
        GROUP BY desc_lvl_1
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
                    (4, 'collection/no info'),
                    (5, 'billing') AS origin(id, description)
    )
    UNION ALL
    (
        WITH cte_payment_status AS (
            SELECT
                DISTINCT status AS desc_lvl_1
            FROM
                datalake_rental_guarantee_platform_clean.payment
            UNION ALL
            SELECT
                DISTINCT status AS desc_lvl_1
            FROM
                datalake_rental_guarantee_platform_clean.agreement_payment
        )
        SELECT
            'Payment Status' AS desc_master_type,
            ROW_NUMBER() OVER( ORDER BY desc_lvl_1 ASC) AS id_lvl_1,
            desc_lvl_1
        FROM
            cte_payment_status
        GROUP BY desc_lvl_1
    )
    UNION ALL
    (
        WITH cte_payment_gateway AS (
            SELECT
                name AS desc_lvl_1
            FROM
                datalake_velo_clean.fiancavelo_gateway
            WHERE name NOT IN (SELECT DISTINCT gateway FROM datalake_rental_guarantee_platform_clean.payment)
            UNION ALL
            SELECT
                DISTINCT gateway AS desc_lvl_1
            FROM
                datalake_rental_guarantee_platform_clean.payment
        )
        SELECT
            'Payment Gateway' AS desc_master_type,
            ROW_NUMBER() OVER( ORDER BY desc_lvl_1 ASC) AS id_lvl_1,
            desc_lvl_1
        FROM
            cte_payment_gateway
        GROUP BY desc_lvl_1
    )
    UNION ALL
    (
        WITH cte_payment_category AS (
            SELECT DISTINCT
                product_type AS desc_lvl_1
            FROM
                datalake_rental_guarantee_platform_clean.payment
            WHERE product_type NOT IN ('GUARANTEE')
            UNION ALL
            SELECT
                name AS desc_lvl_1
            FROM
                VALUES ('AGREEMENT'),
                        ('NO INFO'),
                        ('RECURRING_SUBSCRIPTION') AS origin(name)
        )
        SELECT
            'Payment Category' AS desc_master_type,
            ROW_NUMBER() OVER( ORDER BY desc_lvl_1 ASC) AS id_lvl_1,
            desc_lvl_1
        FROM
            cte_payment_category
        GROUP BY desc_lvl_1
    )
    UNION ALL
    (
        WITH cte_occurrence_status AS (
            SELECT
                name AS desc_lvl_1
            FROM
                VALUES ('REGISTERED'),
                        ('RECOVERING'),
                        ('PROGRESS'),
                        ('FINISHED'),
                        ('UNDER_AGREEMENT'),
                        ('REQUESTED_AGREEMENT') AS origin(name)
        )
        SELECT
            'Occurrence Status' AS desc_master_type,
            ROW_NUMBER() OVER( ORDER BY desc_lvl_1 ASC) AS id_lvl_1,
            desc_lvl_1
        FROM
            cte_occurrence_status
        GROUP BY desc_lvl_1
    )
    UNION ALL
    (
        WITH cte_occurrence_type AS (
            SELECT
                name AS desc_lvl_1
            FROM
                VALUES ('SIGNATURE'),
                        ('GUARANTEE'),
                        ('TERMINATION'),
                        ('BILLING'),
                        ('RENEWAL') AS origin(name)
        )
        SELECT
            'Occurrence Type' AS desc_master_type,
            ROW_NUMBER() OVER( ORDER BY desc_lvl_1 ASC) AS id_lvl_1,
            desc_lvl_1
        FROM
            cte_occurrence_type
        GROUP BY desc_lvl_1
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
