WITH cte_base AS (
    SELECT
        sk_broker,
        sk_propose,
        dt_contract_started
    FROM
        dw_velo.fact_velo_propose
    WHERE
        dt_contract_started is not null
        and sk_broker <> -1
    GROUP BY
        1,2,3
    QUALIFY
        ROW_NUMBER () OVER (PARTITION BY sk_broker ORDER BY dt_contract_started ) = 1
    ORDER BY
        2,3
)

SELECT
    COUNT(sk_broker) AS total_active_broker,
    DATE_TRUNC('month',dt_contract_started) AS month
FROM
    cte_base
GROUP BY
    2
ORDER BY
    2 DESC

