WITH max_ts_value AS (
  SELECT
    lsc.sk_lead_3p_flow,
    l.id_lead_3p,
    COALESCE(lds.sk_listing_draft_status, -1) AS sk_listing_draft_status,
    lsc.business_context,
    l.id_house,
    lsc.status AS current_bsp_status,
    lsc.status_reason AS current_bsp_status_reason,
    lds.current_main_status,
    lds.current_main_status_reason,
    lsc.is_opportunity,
    lsc.growth_status,
    lsc.reason_macro,
    lds.ts_availability_check_start,
    lds.ts_availability_check_end,
    lds.ts_first_listing,
    GREATEST(
      lsc.ts_unpublished_in_bsp,
      lsc.ts_discarded_in_bsp,
      lsc.ts_first_not_converted_in_bsp,
      lsc.ts_last_not_converted_in_bsp,
      lsc.ts_first_processing_photos_in_bsp,
      lsc.ts_last_processing_photos_in_bsp,
      lsc.ts_suspended_in_bsp,
      lsc.ts_first_registered_from_bsp_to_main,
      lds.ts_availability_check_start,
      lds.ts_availability_check_end,
      lds.ts_first_listing
    ) AS ts_max_value
  FROM
    datalake_3p_supply.lead_3p AS l
  LEFT JOIN
    datalake_3p_supply.lead_3p_status_changes AS lsc
    ON l.id_lead_3p = lsc.id_lead_3p
    AND lsc.is_current = TRUE
  LEFT JOIN
    datalake_3p_supply.listing_draft_status AS lds
    ON l.id_house = lds.id_house
    AND lsc.business_context = lds.business_context
)
SELECT
  sk_lead_3p_flow,
  id_lead_3p AS sk_lead_3p,
  sk_listing_draft_status,
  COALESCE(id_house, -1) AS sk_house,
  business_context,
  CASE
    WHEN ts_first_listing IS NOT NULL THEN 'FIRST_LISTING'
    WHEN ts_max_value = ts_availability_check_start THEN 'AVAILABILITY_CHECK_START'
    WHEN ts_max_value = ts_availability_check_end THEN 'AVAILABILITY_CHECK_END'
    WHEN current_bsp_status = 'PROCESSING' THEN 'PROCESSING_PHOTOS'
    WHEN current_bsp_status = 'NOT_CONVERTED' AND is_opportunity THEN 'OPPORTUNITY'
    WHEN current_bsp_status IN ('NOT_CONVERTED', 'UNPUBLISHED', 'REGISTERED', 'SUSPENDED', 'DISCARDED') THEN CONCAT(current_bsp_status, '_BSP')
    ELSE 'OTHER'
  END AS current_conversion_funnel,
  growth_status,
  reason_macro,
  current_bsp_status,
  current_bsp_status_reason,
  current_main_status,
  current_main_status_reason,
  ts_max_value AS ts_last_conversion_funnel_change,
  CURRENT_TIMESTAMP() AS ts_load,
  YEAR(ts_max_value) AS year,
  MONTH(ts_max_value) AS month,
  DAY(ts_max_value) AS day
FROM
  max_ts_value
