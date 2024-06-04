WITH inspections AS (
  SELECT
    inspections.id_inspection AS `id_inspection`,
    (
      DATE(
        TO_TIMESTAMP(CAST(NULLIF(inspection_dates.sk_inspected_date, -1) AS STRING), 'yyyyMMdd')
      )
    ) AS `inspection_date`,
    (
      DATE(contract_termination.dt_termination)
    ) AS `termination_date`,
    region_info.city_name AS `city_name`
  FROM dw_public.dim_inspection AS inspections
  LEFT JOIN dw_public.fact_inspection_bookings AS inspection_dates
    ON inspection_dates.sk_inspection = inspections.sk_inspection
  LEFT JOIN dw_rent.dim_house_listing AS listing_info
    ON inspection_dates.sk_house_listing = listing_info.sk_house_listing
  LEFT JOIN dw_rent.fact_house_listings AS fact_house_listings
    ON listing_info.sk_house_listing = fact_house_listings.sk_house_listing
  LEFT JOIN dw_rent.dim_contract AS public_dim_contract
    ON public_dim_contract.sk_contract = inspection_dates.sk_contract
  LEFT JOIN sql_inspections_contract_termination AS contract_termination
    ON contract_termination.id_contract = public_dim_contract.sk_contract
  LEFT JOIN dw_public.dim_region AS region_info
    ON fact_house_listings.sk_region = region_info.sk_region
  WHERE
    (
      inspections.status
    ) IN ('Comentada', 'EmRevisao', 'Finalizada', 'Revisada')
    AND (
      inspections.type
    ) = 'Saida'
    AND (
      (
        NOT (
          (
            TO_TIMESTAMP(CAST(NULLIF(inspection_dates.sk_inspected_date, -1) AS STRING), 'yyyyMMdd')
          )
        ) IS NULL
      )
    )
    AND (
      NOT (
        contract_termination.is_termination_canceled
      )
      OR (
        contract_termination.is_termination_canceled
      ) IS NULL
    )
  GROUP BY
    1,
    2,
    3,
    4
), sql_inspections_contract_termination AS (
  SELECT
    *,
    CAST(COALESCE(CAST(CAST(DATE_FORMAT(DATE(dt_termination), 'yyyyMMdd') AS STRING) AS INT), -1) AS BIGINT) AS sk_termination_date
  FROM first_termination
  WHERE
    rk = 1
), first_termination AS (
  SELECT
    *,
    RANK() OVER (PARTITION BY id_contract ORDER BY ts_created DESC) AS rk
  FROM datalake_offboarding.contract_termination
  ORDER BY
    rk NULLS LAST
)
SELECT DISTINCT
  i.id_inspection,
  DATEDIFF(DAY, CAST(inspection_date AS TIMESTAMP), CAST(termination_date AS TIMESTAMP)) - DATEDIFF(WEEK, CAST(inspection_date AS TIMESTAMP), CAST(termination_date AS TIMESTAMP)) - DATEDIFF(WEEK, CAST(inspection_date AS TIMESTAMP), CAST(termination_date AS TIMESTAMP)) - COUNT(sch.dt_holiday) OVER (PARTITION BY id_inspection) AS leadtime
FROM inspections AS i
LEFT JOIN datalake_gsheets_clean.service_city_holidays AS sch
  ON sch.dt_holiday BETWEEN i.inspection_date AND i.termination_date
  AND sch.city = i.city_name
WHERE
  NOT termination_date IS NULL