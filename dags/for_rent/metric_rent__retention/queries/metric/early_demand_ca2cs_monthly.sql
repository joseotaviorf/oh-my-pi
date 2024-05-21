WITH 
calculations AS (
  SELECT
    dt.month_start AS dt_reference_month,
    dr.country_code,
    CASE
        WHEN dhl.rent < 1500 THEN 'LOW'
        WHEN dhl.rent < 2500 THEN 'MEDIUM'
        ELSE 'HIGH'
    END AS value_segment,
    COUNT(DISTINCT sk_event) FILTER (WHERE fde.sk_event_type = 8) AS credit_approved,
    COUNT(DISTINCT sk_event) FILTER (WHERE fde.sk_event_type = 9) AS contracts_signed
  FROM
    dw_rent.fact_rent_demand_events AS fde
  JOIN
    dw_public.dim_date AS dt
      ON (dt.sk_date = fde.sk_event_date)
  JOIN
    dw_rent.dim_house_listing AS dhl
      ON fde.sk_house_listing = dhl.sk_house_listing
  JOIN
    dw_public.dim_region AS dr
      ON fde.sk_region = dr.sk_region
  WHERE
    dt.date < CURRENT_DATE()
    AND dhl.is_b2b IS NOT NULL
    AND dhl.ts_early_demand_started IS NOT NULL
  GROUP BY
    1, 2, 3
)

SELECT
  dt_reference_month,
  COALESCE(country_code, 'Undefined') AS country_code,
  value_segment,
  credit_approved,
  contracts_signed,
  contracts_signed / credit_approved AS ca2cs
FROM
  calculations

UNION ALL

SELECT
  dt_reference_month,
  COALESCE(country_code, 'Undefined') AS country_code,
  'OVERALL' AS value_segment,
  SUM(credit_approved) AS credit_approved,
  SUM(contracts_signed) AS contracts_signed,
  SUM(contracts_signed) / SUM(credit_approved) AS ca2cs
FROM
  calculations
GROUP BY
  1, 2, 3