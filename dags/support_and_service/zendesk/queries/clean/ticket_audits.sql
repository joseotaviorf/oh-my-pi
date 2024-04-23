SELECT
  id,
  author_id AS id_author,
  ticket_id AS id_ticket,
  events,
  via,
  dt AS dt_extracted,
  created_at AS ts_created,
  YEAR(CAST(dt AS DATE)) AS year,
  MONTH(CAST(dt AS DATE)) AS month,
  DAY(CAST(dt AS DATE)) AS day
FROM
  datalake_zendesk_raw.ticket_audits
WHERE
  dt = MAKE_DATE({year}, {month}, {day})
