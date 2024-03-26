WITH

base_total AS (
    SELECT
        e.dt_register AS dt_emission,
        DATE_TRUNC('MONTH', e.dt_register) AS month_year,
        'omie' AS platform,
        c.description AS category,
        e.sk_transaction AS id_delinquency,
        e.sk_propose AS id_propose,
        e.due_amount AS total_emissoes
    FROM
        dw_velo.fact_velo_transaction_entries e
    LEFT JOIN
        dw_velo.dim_velo_transaction_category c
        ON c.sk_category = e.sk_category
    LEFT JOIN
        dw_velo.dim_velo_transaction t
        ON e.sk_transaction = t.sk_transaction
    WHERE
        t.transaction_type = 'CONTA_A_RECEBER'
        AND c.description IN ('Alugueis','Condominio','Rescisão','Danos ao Imóvel')
        AND e.dt_register >= DATE('2023-01-01')

    UNION ALL

    SELECT
        CAST(d.ts_created AS DATE) AS dt_register,
        DATE_TRUNC('MONTH', d.ts_created) AS month_year,
        'delinquency' AS platform,
        IF(d.id_type = 1, 'Garantia', 'Rescisao') AS category,
        d.id AS id_delinquency,
        d.id_propose AS id_propose,
        d.original_value AS total_emissoes
    FROM
        datalake_rental_guarantee_platform_clean.delinquency d
    WHERE
        d.is_active = true
        AND d.id_type IN (1,2) -- 0 = Assinatura; 1 = Garantia; 2 = Rescisão; 3 = Billing Direto.
        AND (d.id < 15 OR d.id >= 5000000)
        AND d.ts_created >= CAST('2023-07-01' AS DATE)
),

aux_vol AS (
    SELECT
        dt_emission,
        id_delinquency,
        COUNT(DISTINCT IF(category = 'Alugueis',id_delinquency,null)) AS vol_aluguel,
        COUNT(DISTINCT IF(category = 'Condominio',id_delinquency,null)) AS vol_condominio,
        COUNT(DISTINCT IF(category = 'Danos ao Imóvel',id_delinquency,null)) AS vol_danos,
        COUNT(DISTINCT IF(category = 'Garantia',id_delinquency,null)) AS vol_garantia,
        COUNT(DISTINCT IF(category IN ('Rescisao','Rescisão'),id_delinquency,null)) AS vol_rescisao

    FROM 
        base_total
    WHERE 
        dt_emission >= DATE('2023-01-01')
    GROUP BY 1,2
    ORDER BY 1
),

aux_category AS(
    SELECT
        base_total.month_year,
        aux_vol.id_delinquency,
        CASE
            WHEN aux_vol.vol_rescisao > 0 OR aux_vol.vol_danos > 0  THEN 'rescisao'
            ELSE 'garantia'
        END AS category
    FROM
        base_total
    LEFT JOIN
        aux_vol
        ON aux_vol.dt_emission = base_total.dt_emission
    WHERE
        base_total.dt_emission >= DATE('2023-01-01')
    GROUP BY
        1,2,3
)

SELECT
    base_total.dt_emission,
    SUM(IF(aux_category.category ='garantia',total_emissoes,NULL)) AS sum_guarantee,
    SUM(IF(aux_category.category ='rescisao',total_emissoes,NULL)) AS sum_termination,
    sum(total_emissoes) AS total_emission,
    COUNT(DISTINCT IF(aux_category.category ='garantia', base_total.id_delinquency,NULL)) AS count_guarantee,
    COUNT(DISTINCT IF(aux_category.category ='rescisao', base_total.id_delinquency,NULL)) AS count_termination,
    count(distinct base_total.id_delinquency) AS count_total_emission
FROM
    base_total
INNER JOIN
    aux_category
    ON aux_category.id_delinquency = base_total.id_delinquency
GROUP BY
    1
