WITH relisting AS (
  SELECT
    CAST(CAST(id_house AS STRING)||'00'||CAST(listing_version AS STRING) AS BIGINT) AS id_house_listing,
    id_house,
    country_code,
    listing_version,
    ts_state_started AS ts_early_relisting_started
  FROM 
    datalake_ebdb_listing.lbc_status_version_order
  WHERE 
    status = 'PUBLISHED'
    AND status_reason like 'RELISTING'
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_house, listing_version ORDER BY ts_state_started, ts_state_ended) = 1
),
demand AS (
  SELECT
    CAST(CAST(id_house AS STRING)||'00'||CAST(listing_version AS STRING) AS BIGINT) AS id_house_listing,
    id_house,
    country_code,
    listing_version,
    ts_state_started AS ts_early_demand_started
  FROM 
    datalake_ebdb_listing.lbc_status_version_order
  WHERE 
    status = 'PUBLISHED'
    AND status_reason like 'RELISTING_%'
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_house, listing_version ORDER BY ts_state_started, ts_state_ended) = 1
)
SELECT 
  CAST(CAST(lbc_version.id_house AS STRING)||'00'||CAST(lbc_version.listing_version AS STRING) AS BIGINT) AS id_house_listing,
  lbc_version.id_house,
  lbc_version.country_code,
  lbc_version.listing_version,
  IF(relisting.id_house_listing IS NOT NULL, TRUE, FALSE) AS is_early_relisting,
  IF(demand.id_house_listing IS NOT NULL, TRUE, FALSE) AS is_early_demand,
  ts_early_demand_started
FROM 
  datalake_ebdb_listing.lbc_status_version_order AS lbc_version
LEFT JOIN 
  relisting ON 
    relisting.id_house = lbc_version.id_house
    AND relisting.listing_version = lbc_version.listing_version
LEFT JOIN 
  demand ON 
    demand.id_house = lbc_version.id_house
    AND demand.listing_version = lbc_version.listing_version
GROUP BY
  1,2,3,4,5,6,7