WITH
early_relisting_house_state AS (
  SELECT
      bch.id_house,
      bch.country_code,
      bch.status,
      bch.status_reason,
      bch.suspension_reason,
      bch.ts_state_started,
      bch.ts_state_ended,
      ure.id_user,
      TRUE AS is_early_demand
  FROM
    datalake_ebdb_listing.business_context_history AS bch
  JOIN 
    datalake_ebdb_clean.user_revision_entity AS ure
      ON bch.rev = ure.id
  WHERE
      bch.business_context = 'RENT'
      AND bch.status = 'PUBLISHED'
      AND bch.status_reason LIKE 'RELISTING_%'
      AND bch.suspension_reason = 'RELISTING'
      AND ure.id_user != 4299181 --This filters data inputed by a faulty script. This rule will be replaced in the near future.
), early_relisting_dates AS (
  SELECT 
    hl.id_house_listing,
    hl.id_house,
    hs.country_code,
    hs.status,
    hs.status_reason,
    hs.suspension_reason,
    hs.is_early_demand,
    IF(hs.is_early_demand, hs.ts_state_started, NULL) AS ts_early_demand_started,
    IF(hs.is_early_demand, hs.ts_state_ended, NULL) AS ts_early_demand_ended,
    hs.ts_state_started
  FROM 
    early_relisting_house_state AS hs
  JOIN 
    datalake_ebdb_listing.house_listing_category AS hl 
      ON hl.id_house = hs.id_house
        AND hs.ts_state_started BETWEEN hl.ts_listing_version_start AND COALESCE(hl.ts_listing_version_end, '2700-01-01')
),
early_relisting_date_selection AS (
  SELECT 
    id_house_listing,
    id_house,
    country_code,
    status,
    status_reason,
    suspension_reason,
    is_early_demand, 
    MIN(ts_early_demand_started) AS ts_early_demand_started,
    MIN(ts_early_demand_ended) AS ts_early_demand_ended
  FROM 
    early_relisting_dates
  GROUP BY 
    id_house_listing,
    id_house,
    country_code,
    status,
    status_reason,
    suspension_reason,
    is_early_demand
), 
house_lbc_state AS (
  SELECT 
    id_house,
    country_code,
    status,
    status_reason,
    suspension_reason,
    ts_state_started,
    ts_state_ended,
    ROW_NUMBER() OVER(PARTITION BY id_house ORDER BY ts_state_started DESC) AS state_order
  FROM 
    datalake_ebdb_listing.business_context_history 
  WHERE 
    business_context = 'RENT'
)
SELECT 
  ds.id_house_listing,
  ds.id_house,
  ds.country_code,
  IF(hs.status = 'PUBLISHED' and hs.status_reason = 'RELISTING_OFFER' and hs.suspension_reason = 'RELISTING', TRUE, FALSE) AS is_early_demand,
  CAST(MAX(ds.ts_early_demand_started) AS TIMESTAMP) AS ts_early_demand_started
FROM 
  early_relisting_date_selection AS ds
JOIN house_lbc_state AS hs
  ON hs.id_house = ds.id_house
    AND hs.state_order = 1
GROUP BY 
  1,2, 3, hs.status, hs.status_reason, hs.suspension_reason