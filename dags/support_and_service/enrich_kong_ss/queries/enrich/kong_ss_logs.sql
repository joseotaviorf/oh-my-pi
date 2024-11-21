WITH filtered_logs AS (
  SELECT
    kl.*,
    NULLIF(REGEXP_EXTRACT(kl.message, '(\\d+\.\\d+\.\\d+\.\\d+)', 0), '') AS ip_address,
    NULLIF(REGEXP_EXTRACT(kl.message, '\- (.*) \-'), '') AS request_user,
    NULLIF(REGEXP_EXTRACT(kl.message, '"(.*) \/'), '') AS method,
    NULLIF(REGEXP_EXTRACT(kl.message, '] (.*) "'), '') AS host,
    NULLIF(REGEXP_EXTRACT(kl.message, '".* (\/.*)"'), '') AS endpoint,
    NULLIF(REGEXP_EXTRACT(kl.message, '" ([0-9]{{3}})'), '') AS status_code
  FROM
    datalake_kong_clean.kong_logs AS kl
  WHERE
    MAKE_DATE(kl.year, kl.month, kl.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND kl.message NOT LIKE "%[warn]%"
    AND kl.message NOT LIKE "%[notice]%"
),
entities_extract AS (
  SELECT
    fl.*,
    CASE
      WHEN RLIKE(fl.endpoint, "^/api/") THEN NULLIF(REGEXP_EXTRACT(fl.endpoint, 'api/([^/?]+)/?'), '')
      ELSE NULL
    END AS entity,
    CASE
      WHEN RLIKE(fl.endpoint, "^/api/tasks") THEN NULLIF(REGEXP_EXTRACT(fl.endpoint, 'api/tasks/(\\w+)'), '')
      WHEN RLIKE(fl.endpoint, "^/api/property-bills/property") THEN NULLIF(REGEXP_EXTRACT(fl.endpoint, 'api/property-bills/property/(\\d+)'), '')
      WHEN RLIKE(fl.endpoint, "^/api/offer/client") THEN NULLIF(REGEXP_EXTRACT(fl.endpoint, 'api/offer/client/(\\d+)'), '')
      WHEN RLIKE(fl.endpoint, "^/api/offer/rental") THEN NULLIF(REGEXP_EXTRACT(fl.endpoint, 'api/offer/rental/(\\w+)'), '')
      WHEN RLIKE(fl.endpoint, "^/api/offer/") THEN NULLIF(REGEXP_EXTRACT(fl.endpoint, 'api/offer/(\\w+)/[a-zA-Z+]'), '')
      WHEN RLIKE(fl.endpoint, "^/api/") THEN NULLIF(REGEXP_EXTRACT(fl.endpoint, 'api/[^/?]+/(\\d+)'), '')
      ELSE NULL
    END AS entity_code
  FROM
    filtered_logs AS fl
  WHERE
    fl.request_user IS NOT NULL
    AND (
      fl.host LIKE "%imoveis%"
      OR fl.host LIKE "%crm%"
      OR fl.host LIKE "%magiclink%"
    )
)
SELECT
  ee.app,
  ee.cluster_name,
  ee.container_name,
  ee.endpoint,
  NULLIF(REGEXP_REPLACE(ee.endpoint, CAST(ee.entity_code AS STRING), 'id'), '') AS generic_endpoint,
  kse.description,
  ee.entity,
  ee.entity_code,
  ee.env,
  ee.host,
  ee.ip_address,
  ee.message,
  ee.method,
  ee.namespace,
  ee.pod_name,
  ee.request_user,
  ee.status_code,
  ee.stream,
  ee.ts_event,
  ee.year,
  ee.month,
  ee.day,
  ee.hour
FROM
  entities_extract AS ee
LEFT JOIN
  datalake_gsheets_clean.kong_ss_endpoints AS kse
    ON kse.host = ee.host
    AND kse.endpoint = NULLIF(REGEXP_REPLACE(ee.endpoint, CAST(ee.entity_code AS STRING), 'id'), '')
