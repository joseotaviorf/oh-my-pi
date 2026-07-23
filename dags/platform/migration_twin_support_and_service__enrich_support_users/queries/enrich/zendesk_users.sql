WITH organizations AS (
    SELECT DISTINCT
        id_organization,
        name
    FROM
        datalake_zendesk_clean.organizations
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_organization ORDER BY ts_updated DESC) = 1
),
customer_email AS (
    SELECT DISTINCT
        id_user,
        customer_contact AS email
    FROM
        datalake_ebdb_customer_contact_identification.customer_contact_identification
    WHERE
        channel = 'email'
),
customer_phone AS (
  SELECT DISTINCT
    id_user,
    TRIM(REGEXP_REPLACE(customer_contact, '\\D|^0+', '')) AS phone_number
  FROM
    datalake_ebdb_customer_contact_identification.customer_contact_identification cci_p
  WHERE
    channel = 'phone'
)
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
    u.ts_updated
FROM
    datalake_zendesk_clean.users AS u
LEFT JOIN
    organizations AS o
        ON o.id_organization = u.id_organization
LEFT JOIN
    customer_email AS ce
        ON ce.email = u.email
LEFT JOIN
    customer_phone AS cp
        ON cp.phone_number = REGEXP_REPLACE(u.phone, '\\D|^0+', '')
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY u.id_user ORDER BY u.ts_updated DESC) = 1
