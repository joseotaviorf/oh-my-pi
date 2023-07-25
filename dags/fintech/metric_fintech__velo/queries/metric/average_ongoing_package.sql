with propose_values AS (
    SELECT
        pv.*,
        pv.total_package_amount * pv.plan_percent * 0.01 as mmr
    FROM
        dw_velo.dim_velo_propose_values pv

),
contratos AS (
    SELECT
        pp.sk_propose,
        pp.dt_contract_started AS begin,
        pp.dt_ended,
        SUM(pv.total_package_amount) AS gmv_contract,
        SUM(pv.MMR) AS mmr_contract
    FROM
        dw_velo.fact_velo_propose pp
    LEFT JOIN
        propose_values pv
            ON CAST(pv.sk_propose_values AS BIGINT) = pp.sk_propose_values
    WHERE
        pp.is_contract = TRUE
    GROUP BY
        1,2,3,4

),
novos_contratos AS (

    SELECT
        DATE_TRUNC('month', begin) AS month_signed,
        COUNT(*) AS qty_new_contracts,
        SUM(gmv_contract) AS gmv_new_contracts,
        SUM(mmr_contract) AS mmr_new_contract
    FROM
        contratos
    GROUP BY
        1
),
contratos_encerrados AS (
    SELECT
        DATE_TRUNC('month', dt_ended) as month_signed,
        COUNT(*) as qty_ended_contracts,
        SUM(gmv_contract) as gmv_ended_contracts,
        SUM(mmr_contract) as mmr_ended_contracts
    FROM
        contratos
    GROUP BY
        1

),
totais AS (
    SELECT
        dd.month_start AS month_signed,
        n.qty_new_contracts,
        e.qty_ended_contracts,
        n.gmv_new_contracts,
        e.gmv_ended_contracts,
        n.mmr_new_contract,
        e.mmr_ended_contracts
    FROM
        dw_public.dim_date dd
    LEFT JOIN
        novos_contratos n
            ON dd.month_start = n.month_signed
    LEFT JOIN
        contratos_encerrados e
            ON dd.month_start = e.month_signed
    WHERE
        dd.date < current_date

),
summary AS (
    SELECT
        b1.month_signed,
        b1.qty_new_contracts,
        b1.qty_ended_contracts,
        sum(b2.qty_new_contracts) AS new_accumulated,
        sum(b2.qty_ended_contracts) AS ended_accumulated,
        sum(b2.qty_new_contracts) - sum(b2.qty_ended_contracts) AS qty_active_contracts,
        sum(b2.gmv_new_contracts) - sum(b2.gmv_ended_contracts) AS gmv_active_contracts,
        sum(b2.mmr_new_contract) - sum(b2.mmr_ended_contracts) AS mmr_active_contracts
    FROM
        totais b1
    LEFT JOIN
        totais b2
            ON b1.month_signed >= b2.month_signed
    GROUP BY
        1,2,3
)

SELECT
    month_signed AS month,
    IF(qty_active_contracts = 0, 0, gmv_active_contracts / qty_active_contracts) AS average_package
FROM
    summary
ORDER BY
    1 DESC
