WITH wololo AS (
  SELECT
    id_user,
    'owner_conversion' AS application,
    'WOLOLO' AS source,
    'NSS' AS journey,
    IF(attendance_info IS NOT NULL, TRUE, FALSE) AS has_ops_info,
    GET_JSON_OBJECT(attendance_info, '$.team') AS team,
    COALESCE(GET_JSON_OBJECT(attendance_info, '$.company'), sales_company) AS company,
    GET_JSON_OBJECT(attendance_info, '$.contactType') AS contact_type,
    GET_JSON_OBJECT(attendance_info, '$.contactChannel') AS contact_channel,
    ts_created AS ts_register,
    -1 AS id_agent_olos
  FROM
    datalake_wololo_clean.context_discard
  WHERE
    id_user IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY id_user ORDER BY has_ops_info, ts_register DESC) = 1 -- PEGANDO ÚLTIMO REGISTRO DE CADA ANALISTA
),
users_last_register AS (
  SELECT
    id_agent, 
    email
  FROM
    datalake_olos_dialer_clean.users
  WHERE id_user IS NOT NULL
    AND email IS NOT NULL
    AND email <> ''
  QUALIFY ROW_NUMBER() OVER (PARTITION BY id_agent ORDER BY MAKE_DATE(year, month, day) DESC) = 1
),
campaign_last_register AS (
  SELECT
    id_campaign, 
    description
  FROM
    datalake_olos_dialer_clean.campaign
  QUALIFY ROW_NUMBER() OVER (PARTITION BY id_campaign ORDER BY MAKE_DATE(year, month, day) DESC) = 1
),
last_company AS (
  SELECT
    users.id_agent,
    users.email,
    REPLACE(SPLIT(campaign.description, "_")[0], "5ANDAR", "QUINTO_ANDAR") AS sales_company,
    outbound.ts_started AS ts_register
  FROM
    datalake_olos_dialer_clean.attempts_raw_data outbound
  JOIN
    users_last_register users
      ON users.id_agent = outbound.id_agent
  JOIN
    campaign_last_register AS campaign
      ON campaign.id_campaign = outbound.id_campaign
  QUALIFY ROW_NUMBER() OVER (PARTITION BY users.id_agent ORDER BY MAKE_DATE(year, month, day) DESC) = 1
),
olos AS (
  SELECT 
    u.id AS id_user,
    'owner_conversion' AS application,
    'OLOS' AS source,
    'NSS' AS journey,
    TRUE AS has_ops_info,
    'IS_OUTBOUND' AS team,
    sales_company AS company,
    'ACTIVE' AS contact_type,
    'PHONE_CALL' AS contact_channel,
    u.ts_created AS ts_register,
    olos.id_agent AS id_agent_olos  
  FROM 
    datalake_ebdb_clean.user AS u
  JOIN 
    last_company AS olos
      USING(email)
),
conversion_base AS (
  SELECT
    d.id,
    d.registrar,
    r.id_main,
    d.ops_company,
    d.ops_contact_channel,
    d.ops_contact_type,
    d.ops_team,
    d.ts_created
  FROM
    datalake_bob.house_draft AS d
  JOIN 
    datalake_bob_clean.registrar AS r 
      ON (d.registrar = r.id)
  WHERE
    d.ops_company IS NOT NULL 
  QUALIFY ROW_NUMBER() OVER (PARTITION BY r.id_main ORDER BY ts_created DESC) = 1
),
bob AS (
  SELECT 
    id_main AS id_user,
    'owner_conversion' AS application,
    'BOB' AS source,
    'NSS' AS journey,
    TRUE AS has_ops_info,
    ops_team AS team,
    ops_company AS company,
    ops_contact_type AS contact_type,
    ops_contact_channel AS contact_channel,
    ts_created AS ts_register,
    -1 AS id_agent_olos
  FROM 
    conversion_base
),
all_ops_registers AS (
  SELECT *, 3 AS order
  FROM olos
  UNION ALL
  SELECT *, 2 AS order
  FROM wololo
  UNION ALL
  SELECT *, 1 AS order
  FROM bob
)

SELECT 
  id_user,
  application,
  source,
  journey,
  has_ops_info,
  SF_NORMALIZE_STRING(team) AS ops_agent,
  REPLACE(SF_NORMALIZE_STRING(company), '_', '') AS ops_partner,
  SF_NORMALIZE_STRING(contact_type) AS ops_approach,
  SF_NORMALIZE_STRING(contact_channel) AS ops_contact_medium,
  CASE 
    WHEN team = 'CAPTA_AI' THEN 'acquisition'
    ELSE 'conversion'
  END AS ops_objective,
  ts_register
FROM 
    all_ops_registers
QUALIFY ROW_NUMBER() OVER (PARTITION BY id_user ORDER BY has_ops_info DESC, order) = 1