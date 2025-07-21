WITH amplitude_events AS (
  SELECT
    CASE 
      WHEN LENGTH(TRY_CAST(GET_JSON_OBJECT(ea.event_properties, '$.houseId') AS INT)) < 9 THEN 892700000 + TRY_CAST(GET_JSON_OBJECT(ea.event_properties, '$.houseId') AS INT)
      ELSE TRY_CAST(GET_JSON_OBJECT(ea.event_properties, '$.houseId') AS INT)
    END AS id_house,
    ea.id_user,
    ea.ts_event,
    ea.year,
    ea.month,
    ea.day
    FROM
      datalake_amplitude_agents_app.agents_native_events AS ea
    WHERE
      MAKE_DATE(ea.year, ea.month, ea.day) BETWEEN {'load_start_date'} AND {'load_end_date'}
      AND ea.event_type = "owner_contact_success_page_viewed"
),
agent_data AS (
  SELECT
    uad.id AS id_agent,
    at.types AS agent_type,
    ad.is_active AS is_agent_active,
    ad.agent_type = 'CORRETOR_REDE' AS is_3p_agent,
    uad.is_rent_agent,
    uad.is_sale_agent
  FROM
    datalake_ebdb_user.agent_data AS uad
  LEFT JOIN
    datalake_ebdb_clean.agent_data AS ad
      ON uad.id = ad.id
  LEFT JOIN
    datalake_ebdb_clean.agent_data_types AS at 
      ON at.id_agent_data = uad.id
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY uad.id ORDER BY at.types) = 1
)
SELECT
  CONCAT(h.id, ad.id_agent) AS id,
  h.id AS id_house,
  ad.id_agent,
  FIRST(ea.id_user) AS id_user_agent,
  FIRST(h.id_user) AS id_owner,
  FIRST(ad.agent_type) AS agent_type,
  FIRST(h.city) AS house_city,
  COUNT(ea.ts_event) AS pp_contact_views,
  FIRST(ad.is_agent_active) AS is_agent_active,
  FIRST(ad.is_3p_agent) AS is_3p_agent,
  FIRST(ad.is_rent_agent) AS is_rent_agent,
  FIRST(ad.is_sale_agent) AS is_sale_agent,
  FIRST(ea.ts_event) AS ts_first_pp_contact_view,
  ea.year,
  ea.month,
  ea.day
FROM  
  amplitude_events AS ea
LEFT JOIN
  datalake_ebdb_clean.user AS u
    ON ea.id_user = u.id
INNER JOIN
  agent_data AS ad
    ON u.id_agent = ad.id_agent
INNER JOIN
  datalake_ebdb_clean.house AS h
    ON ea.id_house = h.id
    AND h.is_for_sale
GROUP BY ALL
