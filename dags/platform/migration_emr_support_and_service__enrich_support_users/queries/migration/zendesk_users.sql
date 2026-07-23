WITH organizations AS (
  SELECT
    id_organization,
    name
  FROM (
    SELECT DISTINCT
      id_organization,
      name,
      ROW_NUMBER() OVER (PARTITION BY id_organization ORDER BY ts_updated DESC) AS _w,
      ts_updated
    FROM datalake_zendesk_clean.organizations
  ) AS _t
  WHERE
    _w = 1
), customer_email AS (
  SELECT DISTINCT
    id_user,
    customer_contact AS email
  FROM datalake_ebdb_customer_contact_identification.customer_contact_identification
  WHERE
    channel = 'email'
), customer_phone AS (
  SELECT DISTINCT
    id_user,
    TRIM(REGEXP_REPLACE(customer_contact, '\\D|^0+', '')) AS phone_number
  FROM datalake_ebdb_customer_contact_identification.customer_contact_identification AS cci_p
  WHERE
    channel = 'phone'
)
SELECT
  id_user_zendesk,
  id_user_main,
  id_organization,
  id_external,
  name,
  alias,
  phone,
  role,
  email,
  organization,
  url,
  locale,
  tags,
  ticket_restriction,
  time_zone,
  is_active,
  is_shared_phone_number,
  is_permanently_deleted,
  ts_last_login,
  ts_created,
  ts_updated
FROM (
  SELECT
    u.id_user AS id_user_zendesk,
    COALESCE(ce.id_user, cp.id_user) AS id_user_main,
    u.id_organization,
    u.id_external,
    u.name,
    u.alias,
    u.phone,
    u.role,
    LOWER(u.email) AS email,
    o.name AS organization,
    u.url,
    u.locale,
    u.tags,
    u.ticket_restriction,
    u.time_zone,
    u.is_active,
    u.is_shared_phone_number,
    u.is_permanently_deleted,
    u.ts_last_login,
    u.ts_created,
    u.ts_updated,
    ROW_NUMBER() OVER (PARTITION BY u.id_user ORDER BY u.ts_updated DESC) AS _w,
    u.id_user
  FROM datalake_zendesk_clean.users AS u
  LEFT JOIN organizations AS o
    ON o.id_organization = u.id_organization
  LEFT JOIN customer_email AS ce
    ON ce.email = u.email
  LEFT JOIN customer_phone AS cp
    ON cp.phone_number = REGEXP_REPLACE(u.phone, '\\D|^0+', '')
) AS _t
WHERE
  _w = 1
