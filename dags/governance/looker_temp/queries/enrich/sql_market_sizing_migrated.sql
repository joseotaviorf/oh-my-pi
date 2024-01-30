WITH neighborhoods_qa_present AS (
  SELECT
    dt_reference,
    TRIM(microregion_name_ibge) AS microregion_name_ibge,
    TRIM(city_name_ibge) AS city_name,
    SUM(total_private_households) AS V002_QA
  FROM datalake_gsheets_clean.cities_neighborhoods_ibge_qa
  WHERE
    NOT city_name_qa IS NULL
  GROUP BY
    dt_reference,
    microregion_name_ibge,
    city_name_ibge
), neighborhoods_total AS (
  SELECT
    dt_reference,
    TRIM(microregion_name_ibge) AS microregion_name_ibge,
    TRIM(city_name_ibge) AS city_name,
    SUM(total_private_households) AS V002_IBGE
  FROM datalake_gsheets_clean.cities_neighborhoods_ibge_qa
  GROUP BY
    dt_reference,
    microregion_name_ibge,
    city_name_ibge
), neighborhoods_cities AS (
  SELECT
    ibge.dt_reference,
    ibge.microregion_name_ibge AS microregion_name,
    ibge.city_name,
    COALESCE(qa.V002_QA, 0) AS V002_QA,
    ibge.V002_IBGE
  FROM neighborhoods_total AS ibge
  LEFT JOIN neighborhoods_qa_present AS qa
    ON qa.dt_reference = ibge.dt_reference
    AND qa.city_name = ibge.city_name
    AND qa.microregion_name_ibge = ibge.microregion_name_ibge
), households_qa_grouped AS (
  SELECT
    cities AS city_name,
    microregion_name,
    city_group,
    SUM(CASE WHEN territory_planning = 'Sim' THEN households ELSE 0 END) AS households_qa
  FROM datalake_gsheets_clean.households_per_city_ibge
  GROUP BY
    cities,
    microregion_name,
    city_group
), households_total_grouped AS (
  SELECT
    microregion_name,
    city_group,
    SUM(households) AS households_total
  FROM datalake_gsheets_clean.households_per_city_ibge
  GROUP BY
    microregion_name,
    city_group
), neighborhoods_households AS (
  SELECT
    nc.dt_reference,
    hg.city_name,
    hg.city_group,
    hg.microregion_name,
    hg.households_qa,
    nc.V002_QA,
    nc.V002_IBGE
  FROM neighborhoods_cities AS nc
  LEFT JOIN households_qa_grouped AS hg
    ON nc.city_name = UPPER(hg.city_name)
    AND nc.microregion_name = UPPER(hg.microregion_name)
), grouped_neighborhoods_households AS (
  SELECT
    dt_reference,
    microregion_name,
    city_group,
    SUM(households_qa) AS households_qa,
    SUM(V002_QA) AS V002_QA,
    SUM(V002_IBGE) AS V002_IBGE
  FROM neighborhoods_households
  GROUP BY
    dt_reference,
    microregion_name,
    city_group
), grouped_qa_total_households AS (
  SELECT
    gn.dt_reference,
    gn.microregion_name,
    gn.city_group,
    gn.households_qa,
    ht.households_total,
    gn.V002_QA,
    gn.V002_IBGE
  FROM grouped_neighborhoods_households AS gn
  LEFT JOIN households_total_grouped AS ht
    ON gn.microregion_name = ht.microregion_name AND gn.city_group = ht.city_group
)
SELECT
  gn.dt_reference,
  gn.microregion_name,
  COALESCE(gn.city_group, ms.city_group) AS city_group,
  gn.V002_QA,
  gn.V002_IBGE,
  gn.households_qa,
  gn.households_total,
  ms.vacant_residential_units
FROM datalake_gsheets_clean.marketshare_units_and_tenants AS ms
INNER JOIN grouped_qa_total_households AS gn
  ON EXTRACT(YEAR FROM gn.dt_reference) = EXTRACT(YEAR FROM DATE(ms.dt_year))
  AND gn.microregion_name = ms.microregion