WITH new_contracts AS (
    SELECT
        fvp.dt_contract_started AS day,
        pv.plan_percent,
        COUNT(DISTINCT CASE WHEN(fvp.dt_contract_started IS NOT NULL) THEN fvp.sk_propose ELSE NULL END) AS new_contracts,
        SUM(pv.total_package_amount) AS gmv_new_contracts,
        SUM(pv.monthly_guarantee) AS revenue_new_contracts,
        SUM(pv.activator_amount) AS activation_fee
    FROM
        dw_velo.fact_velo_propose fvp
    LEFT JOIN
        dw_velo.dim_velo_propose_values AS pv 
                ON CAST(pv.sk_propose_values AS BIGINT) = fvp.sk_propose_values
    WHERE
        fvp.dt_contract_started IS NOT NULL
    GROUP BY
        1,2
    ),
    ended_contracts AS (
    SELECT
        fvp.dt_analyst_annulment_input AS day,
        pv.plan_percent,
        COUNT(DISTINCT IF(fvp.dt_analyst_annulment_input IS NOT NULL, fvp.sk_propose, NULL)) AS ended_contracts,
        SUM(pv.total_package_amount) AS gmv_ended_contracts,
        SUM(pv.monthly_guarantee) AS revenue_ended_contracts
    FROM
        dw_velo.fact_velo_propose fvp
    LEFT JOIN
        dw_velo.dim_velo_propose_values AS pv
        ON CAST(pv.sk_propose_values AS BIGINT) = fvp.sk_propose_values
    WHERE
        fvp.dt_analyst_annulment_input IS NOT NULL
        AND fvp.is_contract = TRUE
    GROUP BY
        1,2
    )
    SELECT
        CAST(COALESCE(nc.day, ec.day) AS date) AS date,
        COALESCE(nc.plan_percent, ec.plan_percent) AS plan_percent,
        SUM(new_contracts) AS new_contracts,
        SUM(ended_contracts) AS ended_contracts,
        SUM(gmv_new_contracts) AS gmv_new_contracts,
        SUM(gmv_ended_contracts) AS gmv_ended_contracts,
        SUM(revenue_new_contracts) AS revenue_new_contracts,
        SUM(revenue_ended_contracts) AS revenue_ended_contracts,
        SUM(activation_fee) AS activation_fee
    FROM
        new_contracts nc
    FULL JOIN
        ended_contracts ec
        ON nc.day = ec.day AND nc.plan_percent = ec.plan_percent
    GROUP BY
        1,2
