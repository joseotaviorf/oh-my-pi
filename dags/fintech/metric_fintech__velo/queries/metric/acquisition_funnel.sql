WITH cte_propose AS (
    SELECT
        COUNT(DISTINCT sk_propose) AS qty_PS,
        DATE(ts_propose_started) AS date_ps
    FROM
        dw_velo.fact_velo_propose
    GROUP BY
        DATE(ts_propose_started)
),
cte_ES AS (
    SELECT
        COUNT(DISTINCT sk_propose) AS qty_ES,
        DATE(ts_evaluation_started) AS date_ES
    FROM
        dw_velo.fact_velo_propose
    GROUP BY
        DATE(ts_evaluation_started)
),
cte_CA AS (
    SELECT
        COUNT(DISTINCT sk_propose) AS qty_CA,
        DATE(ts_sign_started) AS date_CA
    FROM
        dw_velo.fact_velo_propose
    GROUP BY
        DATE(ts_sign_started)
),
cte_CS AS (
    SELECT
        COUNT(DISTINCT sk_propose) AS qty_CS,
        DATE(dt_contract_started) AS date_CS
    FROM
        dw_velo.fact_velo_propose
    WHERE
        dt_contract_started IS NOT NULL
    GROUP BY
        DATE(dt_contract_started)
),
cte_ACS AS (
    SELECT
        DATE(dt_contract_started) AS begin,
        COUNT(0) AS qty_active_contract_started
    FROM
        dw_velo.fact_velo_propose AS pp
    WHERE
        dt_ended IS NULL
    GROUP BY
        DATE(dt_contract_started)
)
SELECT
    dd.date,
    SUM(qty_PS) AS propose_created,
    SUM(qty_ES) AS eval_started,
    SUM(qty_CA) AS credit_approved,
    SUM(qty_CS) AS contract_started,
    SUM(qty_active_contract_started) AS active_contract_started,
    SUM(qty_ES) / (sum(qty_PS)*1.0000) AS PC2ES,
    SUM(qty_CS) / (SUM(qty_PS)*1.0000) AS PC2CS,
    SUM(qty_CA) / (SUM(qty_ES)*1.0000) AS ES2CA,
    SUM(qty_CS) / (SUM(qty_CA)*1.0000) AS CA2CS,
    SUM(qty_CS) / (SUM(qty_active_contract_started)*1.0000) AS CS2ACS
FROM
    dw_public.dim_date AS dd
LEFT JOIN
    cte_CS AS ccs
    ON dd.date = ccs.date_CS
LEFT JOIN
    cte_propose cp
    ON dd.date = cp.date_ps
LEFT JOIN
    cte_ES
    ON dd.date = cte_ES.date_ES
LEFT JOIN
    cte_CA
    ON dd.date = cte_CA.date_CA
LEFT JOIN
    cte_ACS
    ON dd.date = cte_ACS.begin
WHERE
    dd.date < current_date
GROUP BY 1
ORDER BY 1 DESC
