WITH cm_actions AS (
  SELECT
    id_contract,
    action_type AS event_name,
    ts_updated AS ts_event
  FROM
    datalake_condominium_payments_clean.condo_monitoring_actions_aud
),
non_payment_report AS (
  SELECT
    npr.id_contract,
    'NON PAYMENT REPORT' AS event_name,
    npr.ts_updated AS ts_event
  FROM
    datalake_condominium_payments_clean.non_payment_report AS npr
  JOIN
    datalake_condominium_payments_clean.condo_monitoring_actions AS cma
      ON npr.id_contract = cma.id_contract
      AND npr.expense_type = 'P'
),
elegibility AS (
  SELECT
    id_contract,
    IF(eligibility, 'ELEGIBLE', NULL) AS event_name,
    ts_updated AS ts_event
  FROM
    datalake_condominium_payments_clean.condo_monitoring_eligibility_aud
),
invoice AS (
  SELECT
    id_contract,
    id AS id_invoice,
    status AS event_name,
    ts_updated AS ts_event
  FROM
    datalake_condominium_payments_clean.invoice_aud
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
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_contract, id_invoice, status ORDER BY ts_sent) = 1
),
events AS (
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
    "ELEGIBILITY" AS source,
    event_name,
    ts_event
  FROM
    elegibility
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
)

SELECT
  e.id_contract,
  e.id_invoice,
  e.id_communication,
  lc.id_house_listing,
  lc.id_house,
  u_owner.uuid_person AS uuid_owner,
  u_tenant.uuid_person AS uuid_tenant,
  e.source,
  e.event_name,
  e.ts_event
FROM
  events AS e
LEFT JOIN
  datalake_listing_contracts.listing_contracts AS lc
    ON e.id_contract = lc.id_contract
LEFT JOIN
  datalake_ebdb_clean.house AS h
    ON lc.id_house = h.id
LEFT JOIN
  datalake_ebdb_clean.user AS u_owner
    ON h.id_user = u_owner.id
LEFT JOIN
  datalake_ebdb_clean.contract AS c
    ON e.id_contract = c.id
LEFT JOIN
  datalake_ebdb_clean.user AS u_tenant
    ON c.id_user = u_tenant.id
