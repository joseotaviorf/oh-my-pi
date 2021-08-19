WITH inspection_booking_retries AS (
  SELECT
    insp.id as id_inspection,
    row_number() over (partition BY c.id, insp.type ORDER BY b.id ASC) AS rn
  FROM datalake_ebdb_clean.contract c
  JOIN datalake_ebdb_clean.inspection insp
    ON c.id = insp.id_contract
  JOIN datalake_ebdb_clean.booking b
	ON insp.id_booking = b.id
)
SELECT -- [ODS] This table was migrated from ODS flow and needs a future refactoring to remove castings and renamings
  insp.id AS sk_inspection,
  COALESCE(insp.id_booking, -1) AS sk_booking,
  -- There is already the 'hl.id_house_listing' that has a similar rule to the below,
  --  however it does not cover NULL cases, so we replicated the ODS concatenation here
  --  to be one hundred percent compliant to the original rule
  CAST(CONCAT(CONCAT(insp.id_house, '00'), COALESCE(hl.version, 1)) AS BIGINT) AS sk_house_listing, -- TODO [ODS] maybe this should be centralized in a dim
  COALESCE(insp.id_user_inspector, -1) AS sk_inspector,
  insp.id_contract AS sk_contract,
  CAST(COALESCE(CAST(DATE_FORMAT(CAST(b.dt_booking AS DATE), 'yyyyMMdd') AS INTEGER), -1) AS BIGINT) AS sk_booking_inspected_date,
  CAST(COALESCE(CAST(DATE_FORMAT(CAST(b.ts_first_canceled_unevaluated AS DATE), 'yyyyMMdd') AS INTEGER), -1) AS BIGINT) AS sk_booking_cancelled_date,
  CAST(COALESCE(CAST(DATE_FORMAT(CAST(insp.dt_inspected AS DATE), 'yyyyMMdd') AS INTEGER), -1) AS BIGINT) AS sk_inspected_date,
  CAST(COALESCE(CAST(DATE_FORMAT(CAST(insp.ts_expired AS DATE), 'yyyyMMdd') AS INTEGER), -1) AS BIGINT) AS sk_expired_date,
  CAST(COALESCE(CAST(DATE_FORMAT(CAST(insp.ts_tenant_approved AS DATE), 'yyyyMMdd') AS INTEGER), -1) AS BIGINT) AS sk_tenant_approved_date,
  CAST(COALESCE(CAST(DATE_FORMAT(CAST(insp.ts_owner_approved AS DATE), 'yyyyMMdd') AS INTEGER), -1) AS BIGINT) AS sk_owner_approved_date,
  CAST(COALESCE(ibr.rn, 1) AS SMALLINT) AS booking_retry_rank_by_inspection_type,
  NOW() AS ts_load
FROM datalake_ebdb_clean.inspection insp
LEFT JOIN datalake_booking.booking b
    ON insp.id_booking = b.id
LEFT JOIN datalake_ebdb_listing.house_listing hl
    ON insp.id_house = hl.id_house
  	AND CAST(insp.ts_created AS DATE) BETWEEN CAST(hl.ts_listing_version_start AS DATE) AND COALESCE(DATE_SUB(CAST(hl.ts_listing_version_end AS DATE), 1), CURRENT_DATE)
LEFT JOIN inspection_booking_retries ibr
    ON ibr.id_inspection = insp.id