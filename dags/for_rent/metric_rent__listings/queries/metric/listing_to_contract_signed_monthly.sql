WITH sums AS (
  SELECT
    DATE_TRUNC('month', dhl.ts_publication) AS month,
    dhl.country_code,
    COUNT(DISTINCT dhl.sk_house_listing) AS total_listings,
    COUNT(DISTINCT fhl.sk_contract) AS new_contracts_signed
  FROM
    dw_rent.dim_house_listing AS dhl
  LEFT JOIN
    dw_rent.fact_house_listings AS fhl
      ON fhl.sk_house_listing = dhl.sk_house_listing
  WHERE
    dhl.ts_publication IS NOT NULL
  GROUP BY 1, 2
)

SELECT
  month,
  country_code,
  FLOAT(new_contracts_signed/total_listings) AS listing_to_contract_signed
FROM
  sums
