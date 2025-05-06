WITH account_manager AS (
  SELECT DISTINCT
    id_owner,
    id_account_manager,
    DATE(ts_account_manager_started) AS dt_account_manager_started,
    DATE(ts_account_manager_ended) AS dt_account_manager_ended
  FROM
    datalake_pro_owners.pro_owner_history
)
SELECT
  hldi.id_house_listing_day AS sk_house_listing_day,
  hldi.id_house_listing AS sk_house_listing,
  hldi.id_house AS sk_house,
  COALESCE(hldi.id_contract, -1) AS sk_contract,
  COALESCE(hldi.id_owner, -1) AS sk_owner,
  COALESCE(am.id_account_manager, -1) AS sk_account_manager,
  COALESCE(oc.id_owner_category, -1) AS sk_owner_category,
  COALESCE(hldi.id_occupant, -1) AS sk_occupant,
  COALESCE(hldi.id_partner, -1) AS sk_partner,
  COALESCE(hldi.id_partner_big_agent, -1) AS sk_partner_big_agent,
  COALESCE(hldi.id_region, -1) AS sk_region,
  COALESCE(hldi.id_house_status, -1) AS sk_house_status,
  COALESCE(cs.sk_company, -1) AS sk_company_supply,
  COALESCE(hldi.id_price_change, -1) AS sk_pricing,
  BIGINT(DATE_FORMAT(DATE(ts_status_started), 'yyyyMMdd')) AS sk_status_started_date,
  BIGINT(COALESCE(DATE_FORMAT(DATE(ts_status_ended), 'yyyyMMdd'), -1)) AS sk_status_ended_date,
  BIGINT(DATE_FORMAT(dt_day, 'yyyyMMdd')) AS sk_date,
  COALESCE(avh.day_available_hours, 0) AS available_hours,
  COALESCE(hldi.listing_page_views, 0) AS page_views,
  COALESCE(hldi.search_results_page_views, 0) AS search_results_page_views,
  COALESCE(hldi.visits_booked, 0) AS visits_booked,
  COALESCE(hldi.visits_completed, 0) AS visits_completed,
  COALESCE(hldi.visits_requested, 0) AS visits_requested,
  COALESCE(hldi.visits_rescheduled, 0) AS visits_rescheduled,
  COALESCE(hldi.visits_confirmed, 0) AS visits_confirmed,
  COALESCE(hldi.visits_done, 0) AS visits_done,
  COALESCE(hldi.offers_sent, 0) AS offers_sent,
  hldi.country_code,
  hldi.year,
  hldi.month,
  hldi.day,
  NOW() AS ts_load
FROM
  datalake_rental_historical_follow_up.house_listings_daily_info AS hldi
LEFT JOIN
  datalake_pro_owners.owner_category AS oc
    ON MAKE_DATE(hldi.year, hldi.month, hldi.day) >= oc.dt_owner_category_started
    AND MAKE_DATE(hldi.year, hldi.month, hldi.day) < COALESCE(oc.dt_owner_category_ended, CURRENT_DATE())
    AND hldi.id_owner = oc.id_owner
LEFT JOIN
  account_manager AS am
    ON hldi.id_owner = am.id_owner
    AND MAKE_DATE(hldi.year, hldi.month, hldi.day) >= am.dt_account_manager_started
    AND MAKE_DATE(hldi.year, hldi.month, hldi.day) < COALESCE(am.dt_account_manager_started, CURRENT_DATE())
LEFT JOIN
  datalake_company.company_sks AS cs
    ON hldi.is_rent_3p_supply
    AND ((
      hldi.uuid_company IS NOT NULL
      AND hldi.uuid_company = cs.uuid_company
    ) OR (
      hldi.uuid_company IS NULL
      AND hldi.id_company_hubspot IS NOT NULL
      AND hldi.id_company_hubspot = cs.id_hubspot
    ) OR (
       hldi.uuid_company IS NULL
       AND hldi.id_company_hubspot IS NULL
       AND hldi.partner_3p_supply = cs.extracted_3p_tag
    ))
LEFT JOIN
  dw_listing.fact_house_listing_daily_available_hours AS avh
    ON avh.sk_house_listing = hldi.id_house_listing
    AND avh.year = hldi.year
    AND avh.month = hldi.month
    AND avh.day = hldi.day
WHERE
  MAKE_DATE(hldi.year, hldi.month, hldi.day) BETWEEN DATE("{load_start_date}") AND DATE("{load_end_date}")
  AND hldi.is_for_rent = TRUE
