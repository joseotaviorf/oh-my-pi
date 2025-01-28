SELECT
  UUID() AS id,
  CONCAT(dl.id_house, dd.year, dd.month, dd.day) AS business_id,
  fl.sk_region AS location_id,
  dl.id_house AS property_id,
  se.sk_owner AS owner_id, 
  ciq.id_partner AS partner_id, 
  fl.sk_user_registration AS user_registration_id, 
  'RENT' AS business_context,
  SUM(di.visits_completed) AS total_visits_completed,
  dd.date AS ts_event,
  dd.year,
  dd.month,
  dd.day
FROM
  dw_rent.fact_house_listing_daily_infos AS di
INNER JOIN
  dw_rent.dim_house_listing AS dl
    ON dl.id_house = di.sk_house
      AND dl.is_last_version = TRUE
INNER JOIN
  dw_rent.fact_house_listings AS fl
    ON fl.sk_house_listing = dl.sk_house_listing
INNER JOIN 
  dw_growth.fact_supply_events AS se
    ON se.sk_house = dl.id_house 
      AND se.sk_funnel_step = 12 -- first listing step
LEFT JOIN 
  datalake_ebdb_agents.ciq_users AS ciq 
    ON ciq.id_user = se.sk_user_affiliate
      AND ciq.is_last_status
LEFT JOIN 
  dw_public.dim_date AS dd 
    ON dd.sk_date = di.sk_date
WHERE
  MAKE_DATE(dd.year, dd.month, dd.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND dl.status IN ('publicado', 'PUBLISHED')
GROUP BY
  ALL
HAVING
  SUM(di.visits_completed) > 0