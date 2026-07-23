WITH user_affiliates AS (
  SELECT
    id,
    id_affiliates,
    id_agent,
    main_phone_ddd,
    ts_updated
  FROM (
    SELECT
      u.id,
      u.id_affiliates,
      u.id_agent,
      u.main_phone_ddd,
      u.ts_updated,
      ROW_NUMBER() OVER (PARTITION BY u.id_affiliates ORDER BY u.ts_updated DESC) AS _w
    FROM datalake_ebdb_user.user AS u
  ) AS _t
  WHERE
    _w = 1
), min_operation_start_rev AS (
  SELECT
    id_affiliate_data,
    MIN(REV) AS REV
  FROM datalake_ebdb_clean.affiliate_data_aud
  WHERE
    NOT ts_operation_start IS NULL
  GROUP BY
    1
), first_operation_start AS (
  SELECT
    ada.id_affiliate_data,
    ada.ts_operation_start
  FROM min_operation_start_rev AS mosr
  LEFT JOIN datalake_ebdb_clean.affiliate_data_aud AS ada
    ON mosr.id_affiliate_data = ada.id_affiliate_data AND mosr.REV = ada.REV
)
SELECT
  ad.id,
  ad.id_indicated_by,
  ad.id_doorman_affiliate_data,
  COALESCE(ur.country_code, 'Undefined') AS country_code,
  ad.is_active,
  (
    NOT ad.id_doorman_affiliate_data IS NULL
  ) AS is_doorman_affiliate,
  ad.origin,
  CASE
    WHEN ad.affiliate_type = 'Doorman' AND NOT u.id_agent IS NULL
    THEN 'Doorman & Agent'
    WHEN NOT u.id_agent IS NULL
    THEN 'Agent'
    ELSE ad.affiliate_type
  END AS affiliate_type,
  ad.payment_preference,
  ad.creci_number,
  COALESCE(ad.operation_city, dad.work_city) AS work_city,
  ad.last_week_balance_communication,
  dad.ts_joined AS ts_doorman_joined,
  COALESCE(fos.ts_operation_start, ad.ts_operation_start) AS ts_first_operation_start,
  ad.ts_operation_start,
  ad.ts_created,
  ad.ts_updated
FROM datalake_ebdb_clean.affiliate_data AS ad
LEFT JOIN user_affiliates AS u /* Adding an CTE to deduplicate some affiliates id */
  ON u.id_affiliates = ad.id
LEFT JOIN datalake_ebdb_country.user AS ur
  ON u.id = ur.id_user
LEFT JOIN datalake_ebdb_clean.doorman_affiliate_data AS dad
  ON dad.id = ad.id_doorman_affiliate_data
LEFT JOIN first_operation_start AS fos
  ON fos.id_affiliate_data = ad.id