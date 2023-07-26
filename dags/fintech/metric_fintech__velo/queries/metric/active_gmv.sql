with propose_values AS (
    SELECT
        pv.*
    FROM
        dw_velo.dim_velo_propose_values AS pv

),
contratos AS (
    SELECT
        pp.sk_propose,
        pp.dt_contract_started AS begin,
        pp.dt_ended AS dt_cancelamento,
        SUM(pv.total_package_amount) AS gmv_contrato
    FROM
        dw_velo.fact_velo_propose AS pp
    LEFT JOIN
        propose_values AS pv
            ON CAST(pv.sk_propose_values AS BIGINT) = pp.sk_propose_values
    WHERE
        pp.is_contract = TRUE
    GROUP BY
        1,2,3

),
novos_contratos AS (
    SELECT
        DATE_TRUNC('day', begin) AS month_signed,
        COUNT(*) AS novos_contratos,
        SUM(gmv_contrato) AS gmv_novos_contratos
    FROM
        contratos
    GROUP BY
        1
    ORDER BY 1 DESC
),
contratos_encerrados AS (
    SELECT
        DATE_TRUNC('day', dt_cancelamento) as month_signed,
        COUNT(*) as contratos_encerrados,
        SUM(gmv_contrato) as gmv_contratos_encerrados
    FROM
        contratos
    GROUP BY
        1
    ORDER BY 1 DESC

),
totais AS (
    SELECT
        dd.date AS month_signed,
        n.novos_contratos,
        e.contratos_encerrados,
        n.gmv_novos_contratos AS gmv_novos_contratos,
        e.gmv_contratos_encerrados AS gmv_contratos_encerrados
    FROM
        dw_public.dim_date dd
    LEFT JOIN
        novos_contratos n
            ON dd.date = n.month_signed
    LEFT JOIN
        contratos_encerrados e
            ON dd.date = e.month_signed
    WHERE
        dd.date < current_date
    ORDER BY 1 DESC
)
SELECT
    b1.month_signed,
    sum(b2.gmv_novos_contratos) - sum(b2.gmv_contratos_encerrados) AS gmv_active_contracts
FROM
    totais b1
LEFT JOIN
    totais b2
        ON b1.month_signed >= b2.month_signed
GROUP BY
    1
ORDER BY
    1 DESC
