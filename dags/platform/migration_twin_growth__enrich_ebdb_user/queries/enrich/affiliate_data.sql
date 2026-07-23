WITH user_affiliates AS (
  SELECT 
    u.id, 
    u.id_affiliates, 
    u.id_agent,
    u.main_phone_ddd,
    u.ts_updated
  FROM datalake_ebdb_user.user AS u
  QUALIFY ROW_NUMBER() OVER(PARTITION BY u.id_affiliates ORDER BY u.ts_updated DESC) = 1    
),

min_operation_start_rev (
    SELECT
        id_affiliate_data,
        MIN(REV) AS REV
    FROM datalake_ebdb_clean.affiliate_data_aud
    WHERE ts_operation_start IS NOT NULL
    GROUP BY 1
),

first_operation_start (
	SELECT
	    ada.id_affiliate_data,
	    ada.ts_operation_start
	FROM min_operation_start_rev mosr
    LEFT JOIN datalake_ebdb_clean.affiliate_data_aud ada
        ON mosr.id_affiliate_data = ada.id_affiliate_data
        AND mosr.REV = ada.REV
)

SELECT
    ad.id,
    ad.id_indicated_by,
    ad.id_doorman_affiliate_data,
    COALESCE(ur.country_code, 'Undefined') AS country_code,
    ad.is_active,
    (ad.id_doorman_affiliate_data IS NOT NULL) AS is_doorman_affiliate,
    ad.origin,
    CASE WHEN ad.affiliate_type = 'Doorman' AND u.id_agent IS NOT NULL THEN 'Doorman & Agent'
         WHEN u.id_agent IS NOT NULL THEN 'Agent'
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
LEFT JOIN user_affiliates AS u    -- Adding an CTE to deduplicate some affiliates id
    ON u.id_affiliates = ad.id          
LEFT JOIN datalake_ebdb_country.user AS ur
        ON u.id = ur.id_user
LEFT JOIN datalake_ebdb_clean.doorman_affiliate_data AS dad
    ON dad.id = ad.id_doorman_affiliate_data
LEFT JOIN first_operation_start AS fos
    ON fos.id_affiliate_data = ad.id