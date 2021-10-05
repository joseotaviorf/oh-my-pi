WITH agents_with_keys AS (
  SELECT
    id_house_listing,
    MIN(first_key_location) AS first_key_location,
    MIN(is_keys_with_agent_eligible) AS is_keys_with_agent_eligible
  FROM
    datalake_ebdb_listing_prod.agents_with_keys
  GROUP BY 1
)
SELECT
  hl.id_house_listing,
  id_house,
  version,
  awk.first_key_location,
  status,
  cast(rent as decimal(12,2)) as rent,
  listing_category,
  last_originals_type,
  last_iorent_type,
  is_last_version,
  is_exclusive,
  awk.is_keys_with_agent_eligible,
  is_originals_active,
  is_iorent_active,
  ts_listing_version_start,
  ts_listing_version_end,
  ts_last_unpublished,
  dt_last_exclusive_opted_in,
  dt_last_exclusive_opted_out,
  dt_last_originals_opted_in,
  dt_last_originals_opted_out,
  dt_last_iorent_opted_in,
  dt_last_iorent_opted_out
 FROM 
    datalake_ebdb_listing_prod.house_listing AS hl
 LEFT JOIN
    agents_with_keys AS awk
      ON hl.id_house_listing = awk.id_house_listing