WITH ebdb_users AS (
  SELECT
    id_user,
    TRIM(LOWER(email)) AS email,
    main_phone AS phone_number
  FROM
    datalake_ebdb_clean.user_aud
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_user ORDER BY rev DESC) = 1
),
hub_services_users AS (
  SELECT
    id_visitor,
    phone_number,
    email
  FROM
    datalake_sale_lead_flows.hub_services_lead_flow
),
match_email AS (
  SELECT
    u.id_user,
    c.id_visitor
  FROM
    ebdb_users AS u
  JOIN
    hub_services_users AS c
      ON u.email = c.email
),
match_phone AS (
  SELECT
    u.id_user,
    c.id_visitor
  FROM
    ebdb_users AS u
  JOIN
    hub_services_users AS c
      ON u.phone_number = c.phone_number
  LEFT JOIN
    match_email AS me
      ON me.id_user = u.id_user
      OR me.id_visitor = c.id_visitor
  WHERE
    me.id_user IS NULL
    AND me.id_visitor IS NULL
),
match_5a AS (
  SELECT
    me.id_user,
    me.id_visitor
  FROM
    match_email AS me
  UNION ALL
  SELECT
    mp.id_user,
    mp.id_visitor
  FROM
    match_phone AS mp
),
consolidated_users AS (
  SELECT
    COALESCE(m.id_user, u.id_user) AS id_user,
    COALESCE(m.id_visitor, c.id_visitor) AS id_visitor
  FROM
    match_5a AS m
  FULL OUTER JOIN
    ebdb_users AS u
      ON u.id_user = m.id_user
  FULL OUTER JOIN
    hub_services_users AS c
      ON c.id_visitor = m.id_visitor
  WHERE
    m.id_user IS NOT NULL
    AND m.id_visitor IS NOT NULL
),
max_date AS (
  SELECT
    id_visitor,
    ts_created,
    lead_type,
    MAX(ts_updated) AS ts_updated
  FROM
    datalake_hub_services_clean.lead_aud
  WHERE
    business_context = 'SALE'
    AND is_secretariat = true
    AND ts_updated >= DATE('2022-01-01')
  GROUP BY
    1,2,3
),
inner_base AS (
  SELECT
    l.id_visitor,
    l.ts_updated,
    DATE(l.ts_updated) AS data_lead,
    MIN(o.ts_updated) AS ts_observation,
    DATE(MIN(o.ts_updated)) AS data_lead
  FROM
    max_date AS l
  INNER JOIN
    datalake_hub_services_clean.observation o
      ON l.id_visitor = o.id_visitor
      AND DATE(l.ts_updated) BETWEEN DATE(o.ts_updated) AND DATE_ADD(o.ts_updated,3)
  GROUP BY
    1,2,3
),
union_base AS (
  (
    SELECT
      id_visitor,
      IF(lead_type='TALK_TO_SECRETARIA', 'TTS', 'Other') AS lead_type,
      ts_updated,
      DATE(ts_updated) AS date_lead
    FROM
      max_date
  )
  UNION ALL
  (
    SELECT
      id_visitor,
      'Other' AS lead_type,
      ts_updated,
      DATE(ts_updated) AS date_lead
    FROM
      datalake_hub_services_clean.observation
  )
),
deduplicated_base AS (
  SELECT
    u.id_visitor,
    u.ts_updated,
    u.date_lead,
    u.lead_type,
    IF(
      u.id_visitor=i.id_visitor AND u.ts_updated=i.ts_observation, TRUE, FALSE
    ) AS is_duplicated_data
  FROM
    union_base AS u
  LEFT JOIN
    inner_base AS i
      ON u.id_visitor = i.id_visitor
      AND u.ts_updated = i.ts_observation
)

SELECT
  c.id_user,
  IF(d.lead_type = 'TTS', 'SV contact TTS', 'SV contact') AS action,
  date_lead AS dt_event,
  MIN(ts_updated) AS ts_event
FROM
  deduplicated_base AS d
LEFT JOIN
  consolidated_users AS c
    ON d.id_visitor = c.id_visitor
WHERE
  is_duplicated_data = FALSE
  AND c.id_user IS NOT NULL
GROUP BY
  1,2,3
