SELECT
    DATE(DATE_TRUNC('MONTH', dc.ts_termination_requested)) AS dt_month_rescission_created,
    fct_or.country_code,
    'OVERALL' AS category,
    COUNT(DISTINCT 
      IF(
        dhl.ts_early_demand_started IS NOT NULL 
        AND dhl.ts_early_demand_started <= DATEADD(WEEK, 2, dc.ts_termination_requested), dhl.id_house, NULL
      )
    ) AS qtd_houses_early_relisting_2w,
    COUNT(DISTINCT fct_or.sk_house) AS qtd_terminations,
    CAST(
      COUNT(DISTINCT 
        IF(
          dhl.ts_early_demand_started IS NOT NULL 
          AND dhl.ts_early_demand_started <= DATEADD(WEEK, 2, dc.ts_termination_requested), dhl.id_house, NULL
        )
    ) AS DOUBLE) 
    / 
    CAST(
      COUNT(DISTINCT 
        fct_or.sk_house
      ) AS DOUBLE
    ) AS pct_early_demand_opt_in_2w
FROM 
    dw_retention.fact_owner_retention AS fct_or
INNER JOIN
    dw_rent.dim_contract AS dc
        ON dc.sk_contract = fct_or.sk_contract
            AND dc.ts_termination_requested IS NOT NULL
INNER JOIN 
    dw_rent.dim_house_listing AS dhl
        ON dhl.id_house = fct_or.sk_house
GROUP BY 
    1, 2, 3

UNION ALL

SELECT
    DATE(DATE_TRUNC('MONTH', dc.ts_termination_requested)) AS dt_month_rescission_created,
    fct_or.country_code,
    dc.value_segment AS category,
    COUNT(DISTINCT 
      IF(
        dhl.ts_early_demand_started IS NOT NULL 
        AND dhl.ts_early_demand_started <= DATEADD(WEEK, 2, dc.ts_termination_requested), dhl.id_house, NULL
      )
    ) AS qtd_houses_early_relisting_2w,
    COUNT(DISTINCT fct_or.sk_house) AS qtd_terminations,
    CAST(
      COUNT(DISTINCT 
        IF(
          dhl.ts_early_demand_started IS NOT NULL 
          AND dhl.ts_early_demand_started <= DATEADD(WEEK, 2, dc.ts_termination_requested), dhl.id_house, NULL
        )
    ) AS DOUBLE) 
    / 
    CAST(
      COUNT(DISTINCT 
        fct_or.sk_house
      ) AS DOUBLE
    ) AS pct_early_demand_opt_in_2w
FROM 
    dw_retention.fact_owner_retention AS fct_or
INNER JOIN
    dw_rent.dim_contract AS dc
        ON dc.sk_contract = fct_or.sk_contract
            AND dc.ts_termination_requested IS NOT NULL
INNER JOIN 
    dw_rent.dim_house_listing AS dhl
        ON dhl.id_house = fct_or.sk_house
GROUP BY 
    1, 2, 3