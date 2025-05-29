WITH cm_actions AS (
  SELECT
    id_contract,
    action_type AS event_name,
    ts_updated AS ts_event
  FROM
    datalake_rental_management.condo_monitoring_actions_aud
),
non_payment_report AS (
  SELECT
    npr.id_contract,
    'NON_PAYMENT_REPORT' AS event_name,
    npr.ts_updated AS ts_event
  FROM
    datalake_condominium_payments_clean.non_payment_report AS npr
  JOIN
    datalake_rental_management_clean.condo_monitoring_actions AS cma
      ON npr.id_contract = cma.id_contract
      AND npr.expense_type = 'P'
),
eligibility AS (
  SELECT
    id_contract,
    IF(eligibility, 'ELIGIBLE', NULL) AS event_name,
    ts_updated AS ts_event
  FROM
    datalake_rental_management.condo_monitoring_eligibility_aud
),
invoice AS (
  SELECT
    id_contract,
    id AS id_invoice,
    status AS event_name,
    ts_updated AS ts_event
  FROM
    datalake_rental_management.invoice_aud
),
comm AS(
  SELECT
    id_contract,
    id_invoice,
    id_communication,
    communication_type AS event_name,
    ts_sent AS ts_event
  FROM
    datalake_condo_monitoring.communication
),
all_events AS (
  SELECT
    id_contract,
    NULL AS id_invoice,
    NULL AS id_communication,
    "CONDO_MONITORING" AS source,
    event_name,
    ts_event
  FROM
    cm_actions
  UNION ALL
  SELECT
    id_contract,
    NULL AS id_invoice,
    NULL AS id_communication,
    "NON_PAYMENT_REPORT" AS source,
    event_name,
    ts_event
  FROM
    non_payment_report
  UNION ALL
  SELECT
    id_contract,
    NULL AS id_invoice,
    NULL AS id_communication,
    "ELIGIBILITY" AS source,
    event_name,
    ts_event
  FROM
    eligibility
  UNION ALL
  SELECT
    id_contract,
    id_invoice,
    NULL AS id_communication,
    "INVOICE" AS source,
    event_name,
    ts_event
  FROM
    invoice
  UNION ALL
  SELECT
    id_contract,
    id_invoice,
    id_communication,
    "COMMUNICATION" AS source,
    event_name,
    ts_event
  FROM
    comm
),
cm_status AS (
  SELECT
    id_contract,
    action_type,
    LEAD(action_type) OVER(PARTITION BY id_contract ORDER BY ts_updated) AS next_action_type,
    ts_updated AS ts_status_started,
    LEAD(ts_updated) OVER(PARTITION BY id_contract ORDER BY ts_updated) AS ts_status_ended
  FROM
    datalake_rental_management.condo_monitoring_actions_aud
),
cm_active_ts AS (
  SELECT
    id_contract,
    ts_status_started,
    ts_status_ended
  FROM
    cm_status
  WHERE
    action_type = 'ACTIVATED'
),
events AS (
  SELECT
    e.id_contract,
    e.id_invoice,
    e.id_communication,
    hl.id_house_listing,
    hl.id_house,
    u_owner.uuid_person AS uuid_owner,
    u_tenant.uuid_person AS uuid_tenant,
    e.source,
    e.event_name,
    ROW_NUMBER() OVER(PARTITION BY e.id_contract, DATE(e.ts_event) ORDER BY e.ts_event) AS event_number,
    cm_active.id_contract IS NOT NULL AS was_condo_monitoring_active,
    DATE_FORMAT(e.ts_event, "yyyyMMdd") AS dt_event,
    e.ts_event
  FROM
    all_events AS e
  LEFT JOIN
    datalake_ebdb_listing.house_listing AS hl
      ON e.id_contract = hl.id_contract
  LEFT JOIN
    datalake_ebdb_clean.house AS h
      ON hl.id_house = h.id
  LEFT JOIN
    datalake_ebdb_clean.user AS u_owner
      ON h.id_user = u_owner.id
  LEFT JOIN
    datalake_ebdb_clean.contract AS c
      ON e.id_contract = c.id
  LEFT JOIN
    datalake_ebdb_clean.user AS u_tenant
      ON c.id_user = u_tenant.id
  LEFT JOIN
    cm_active_ts AS cm_active
      ON e.id_contract = cm_active.id_contract
      AND e.ts_event >= cm_active.ts_status_started
      AND e.ts_event < COALESCE(cm_active.ts_status_ended, NOW())
)
SELECT
  BIGINT(CONCAT(id_contract, dt_event, '00', event_number)) AS id_condo_monitoring_event,
  id_contract,
  id_invoice,
  id_communication,
  id_house_listing,
  id_house,
  uuid_owner,
  uuid_tenant,
  source,
  event_name,
  was_condo_monitoring_active,
  ts_event
FROM
  events
