WITH leadtime_calculation AS (
  SELECT
    fct.sk_contract,
    dc.value_segment,
    COALESCE(dc.dt_start, dc.dt_entrance) AS dt_start,
    DATEDIFF(DATE(COALESCE(dc.dt_start, dc.dt_entrance)), DATE(dc.ts_created)) leadtime
  FROM
    dw_retention.fact_contract_termination AS fct
  JOIN
    dw_retention.dim_termination AS dt
      ON fct.sk_termination = dt.sk_termination
  JOIN
    dw_rent.fact_house_listings AS fhl
      ON fct.sk_contract = fhl.sk_contract
  JOIN
    dw_rent.dim_house_listing AS dhl
      ON fhl.sk_house_listing + 1 = dhl.sk_house_listing
  JOIN
    dw_rent.fact_listing_rent_flows AS flrf
      ON dhl.sk_house_listing = flrf.sk_house_listing
  JOIN
    dw_rent.dim_contract AS dc
      ON flrf.sk_contract = dc.sk_contract
  WHERE
    dt.status = 'DONE'
    AND dc.status IN ('Ativo', 'Finalizado')
    AND dhl.listing_category_start = 'Re-Listing'
)

SELECT
    DATE(DATE_TRUNC('MONTH', dt_start)) AS dt_reference_month,
    value_segment,
    APPROX_PERCENTILE(leadtime, 0.5) AS median_leadtime,
    COUNT(DISTINCT sk_contract) AS volume_contracts
FROM
    leadtime_calculation
WHERE
    dt_start < CURRENT_DATE()
GROUP BY
    1, 2

UNION ALL

SELECT
    DATE(DATE_TRUNC('MONTH', dt_start)) AS dt_reference_month,
    'OVERALL' AS value_segment,
    APPROX_PERCENTILE(leadtime, 0.5) AS median_leadtime,
    COUNT(DISTINCT sk_contract) AS volume_contracts
FROM
    leadtime_calculation
WHERE
    dt_start < CURRENT_DATE()
GROUP BY
    1, 2