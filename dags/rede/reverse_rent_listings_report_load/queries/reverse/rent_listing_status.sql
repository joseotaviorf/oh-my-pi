SELECT
  UUID() as id,
  CONCAT(dl.id_house, dd.year, dd.month, dd.day) AS business_id,
  dl.id_house AS property_id,
  fl.sk_region AS location_id,
  se.sk_owner AS owner_id, 
  ciq.id_partner AS partner_id,
  fl.sk_user_registration AS user_registration_id, 
  'RENT' AS business_context,
  CASE 
    WHEN ls.status_history = 'alugado' 
      OR (ls.status_history = 'SUSPENDED' AND ls.status_change_reason = 'RENTED') THEN 'RENTED'
    WHEN (ls.status_history = 'SUSPENDED' AND ls.status_change_reason = 'HouseReserved')
      OR (ls.status_history = 'SUSPENDED' AND ls.status_change_reason = 'ContractDraft')  THEN 'RENTAL_PREPARATION'
    WHEN ls.status_history IN ('publicado', 'PUBLISHED') THEN 'PUBLISHED'
    WHEN ls.status_history IN ('despublicado', 'UNPUBLISHED', 'edicao', 'EDITING', 'excluido', 'OPTED_OUT', 'suspenso', 'SUSPENDED') THEN 'UNAVAILABLE'
    ELSE NULL
  END AS status_history,
  dd.date AS ts_event,
  dd.year,
  dd.month,
  dd.day
FROM 
  dw_rent.fact_house_listings AS fl     
INNER JOIN 
  dw_rent.fact_house_listing_status AS ls
    ON fl.sk_house_listing = ls.sk_house_listing
INNER JOIN 
  dw_rent.dim_house_listing AS dl 
    ON dl.sk_house_listing = fl.sk_house_listing
      AND dl.is_last_version = TRUE
LEFT JOIN 
  dw_growth.fact_supply_events AS se
    ON se.sk_house = dl.id_house
      AND se.sk_funnel_step = 12 -- first listing step
LEFT JOIN 
  datalake_ebdb_agents.ciq_users AS ciq
    ON ciq.id_user = fl.sk_user_registration
      AND ciq.is_last_status
INNER JOIN 
  dw_public.dim_date dd
    ON dd.sk_date = ls.sk_status_start_date
WHERE 
  MAKE_DATE(dd.year, dd.month, dd.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND ls.is_last_status_of_day
    AND ls.sk_status_end_date > 0
    AND se.nm_business_context = 'RENT'