WITH wololo AS (
  SELECT
    id_user,
    application,
    source,
    journey,
    has_ops_info,
    team,
    company,
    contact_type,
    contact_channel,
    ts_register
  FROM (
    SELECT
      id_user,
      'owner_conversion' AS application,
      'WOLOLO' AS source,
      'NSS' AS journey,
      IF(NOT attendance_info IS NULL, TRUE, FALSE) AS has_ops_info,
      GET_JSON_OBJECT(attendance_info, '$.team') AS team,
      COALESCE(GET_JSON_OBJECT(attendance_info, '$.company'), sales_company) AS company,
      GET_JSON_OBJECT(attendance_info, '$.contactType') AS contact_type,
      GET_JSON_OBJECT(attendance_info, '$.contactChannel') AS contact_channel,
      ts_created AS ts_register,
      ROW_NUMBER() OVER (PARTITION BY id_user ORDER BY IF(NOT attendance_info IS NULL, TRUE, FALSE), ts_created DESC) AS _w
    FROM datalake_wololo_clean.context_discard
    WHERE
      NOT id_user IS NULL
  ) AS _t
  WHERE
    _w = 1 /* PEGANDO ÚLTIMO REGISTRO DE CADA ANALISTA */
), users_last_register AS (
  SELECT
    id_agent,
    email
  FROM (
    SELECT
      id_agent,
      email,
      ROW_NUMBER() OVER (PARTITION BY id_agent ORDER BY MAKE_DATE(year, month, day) DESC) AS _w,
      year,
      month,
      day
    FROM datalake_olos_dialer_clean.users
    WHERE
      NOT id_user IS NULL AND NOT email IS NULL AND email <> ''
  ) AS _t
  WHERE
    _w = 1
), campaign_last_register AS (
  SELECT
    id_campaign,
    description
  FROM (
    SELECT
      id_campaign,
      description,
      ROW_NUMBER() OVER (PARTITION BY id_campaign ORDER BY MAKE_DATE(year, month, day) DESC) AS _w,
      year,
      month,
      day
    FROM datalake_olos_dialer_clean.campaign
  ) AS _t
  WHERE
    _w = 1
), last_company AS (
  SELECT
    id_agent,
    email,
    sales_company,
    ts_register
  FROM (
    SELECT
      users.id_agent,
      users.email,
      REPLACE(SPLIT(campaign.description, '_')[0], '5ANDAR', 'QUINTO_ANDAR') AS sales_company,
      outbound.ts_started AS ts_register,
      ROW_NUMBER() OVER (PARTITION BY users.id_agent ORDER BY MAKE_DATE(year, month, day) DESC) AS _w,
      year,
      month,
      day
    FROM datalake_olos_dialer_clean.attempts_raw_data AS outbound
    JOIN users_last_register AS users
      ON users.id_agent = outbound.id_agent
    JOIN campaign_last_register AS campaign
      ON campaign.id_campaign = outbound.id_campaign
  ) AS _t
  WHERE
    _w = 1
), olos AS (
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
    u.ts_created AS ts_register
  FROM datalake_ebdb_clean.user AS u
  JOIN last_company AS olos
    USING (email)
), conversion_base AS (
  SELECT
    id,
    registrar,
    id_main,
    ops_company,
    ops_contact_channel,
    ops_contact_type,
    ops_team,
    ts_created
  FROM (
    SELECT
      d.id,
      d.registrar,
      r.id_main,
      d.ops_company,
      d.ops_contact_channel,
      d.ops_contact_type,
      d.ops_team,
      d.ts_created,
      ROW_NUMBER() OVER (PARTITION BY r.id_main ORDER BY ts_created DESC) AS _w
    FROM datalake_bob.house_draft AS d
    JOIN datalake_bob_clean.registrar AS r
      ON (
        d.registrar = r.id
      )
    WHERE
      NOT NULLIF(d.ops_company, '') IS NULL
  ) AS _t
  WHERE
    _w = 1
), ciq /* This CTE is responsible for getting the last record of each analyst into CIQ context,
and needs to be updated when the context of the CIQ create a new model to capture this info */ AS (
  SELECT
    id_user,
    application,
    source,
    journey,
    has_ops_info,
    team,
    company,
    contact_type,
    contact_channel,
    ts_register
  FROM (
    SELECT
      r.id_main AS id_user,
      'owner_conversion' AS application,
      'BOB_AUD' AS source,
      'CIQ' AS journey,
      TRUE AS has_ops_info,
      GET_JSON_OBJECT(d.attendance_info, '$.team') AS team,
      NULLIF(GET_JSON_OBJECT(d.attendance_info, '$.company'), '') AS company,
      CAST(NULL AS STRING) AS contact_type,
      CAST(NULL AS STRING) AS contact_channel,
      d.ts_updated AS ts_register,
      ROW_NUMBER() OVER (PARTITION BY r.id_main ORDER BY d.ts_updated DESC) AS _w,
      r.id_main,
      d.ts_updated
    FROM datalake_bob_clean.house_draft_aud AS d
    JOIN datalake_bob_clean.registrar AS r
      ON (
        d.registrar = r.id
      )
    WHERE
      (
        UPPER(GET_JSON_OBJECT(d.attendance_info, '$.team')) = 'CIQ'
      )
      AND MAKE_DATE(d.year, d.month, d.day) >= CAST('2023-08-01' AS DATE)
  ) AS _t
  WHERE
    _w = 1 /* PEGANDO ÚLTIMO REGISTRO DE CADA ANALISTA */
), bob AS (
  SELECT
    id_main AS id_user,
    'owner_conversion' AS application,
    'BOB' AS source,
    'NSS' AS journey,
    TRUE AS has_ops_info,
    ops_team AS team,
    ops_company AS company,
    NULLIF(ops_contact_type, '') AS contact_type,
    NULLIF(ops_contact_channel, '') AS contact_channel,
    ts_created AS ts_register
  FROM conversion_base
), all_ops_registers AS (
  SELECT
    *,
    1 AS order
  FROM bob
  UNION ALL
  SELECT
    *,
    2 AS order
  FROM wololo
  UNION ALL
  SELECT
    *,
    3 AS order
  FROM ciq
  UNION ALL
  SELECT
    *,
    4 AS order
  FROM olos
)
SELECT
  id_user,
  application,
  source,
  journey,
  has_ops_info,
  ops_agent,
  ops_partner,
  ops_approach,
  ops_contact_medium,
  ops_objective,
  ts_register
FROM (
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
    CASE WHEN team = 'CAPTA_AI' THEN 'acquisition' ELSE 'conversion' END AS ops_objective,
    ts_register,
    ROW_NUMBER() OVER (PARTITION BY id_user ORDER BY has_ops_info DESC, order) AS _w,
    order
  FROM all_ops_registers
) AS _t
WHERE
  _w = 1