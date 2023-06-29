WITH cte_base AS (
    SELECT
        sk_broker,
        sk_propose,
        dt_contract_started
    FROM
        dw_velo.fact_velo_propose
    WHERE
        dt_contract_started IS NOT NULL
        AND sk_broker <> -1
    GROUP BY
        1,2,3
    QUALIFY
        ROW_NUMBER () OVER (PARTITION BY sk_broker ORDER BY dt_contract_started ) = 1
    ORDER BY
        1,3
),
cte_first_activation AS (
    SELECT
        COUNT(sk_broker) AS total_active_broker,
        DATE_TRUNC('month',dt_contract_started) AS month
    FROM
        cte_base
    GROUP BY
        2
    ORDER BY
        2 DESC
),
cte_registered_broker AS (
    SELECT
        DATE_TRUNC('month', DATE(dvb.ts_created)) AS month,
        COUNT(DISTINCT dvb.sk_broker) AS registered_brokers
    FROM
        dw_velo.dim_velo_broker dvb
    LEFT JOIN
        dw_velo.fact_velo_propose fvp
            ON dvb.sk_broker = fvp.sk_broker
    WHERE
        dvb.ts_created IS NOT NULL
    GROUP BY
        1
    ORDER BY
        1 DESC
)
SELECT
    ROUND((CAST(f.total_active_broker AS DECIMAL (20,4)) / CAST(r.registered_brokers AS DECIMAL (20,4))) * 100, 4) AS percent,
    r.month
FROM
    cte_first_activation AS f
LEFT JOIN
    cte_registered_broker r
        ON f.month = r.month
ORDER BY
    2 DESC
