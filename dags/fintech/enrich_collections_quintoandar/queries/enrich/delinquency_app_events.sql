WITH
get_session_start AS (
  SELECT
    e.id_amplitude,
    e.id_session,
    e.id_user,
    c.id_contract,
    e.device_brand,
    e.country,
    e.ts_event
  FROM datalake_amplitude_clean.170698_session_start_events AS e
  LEFT JOIN datalake_ebdb_contract.contract_person AS c
    ON e.id_user = c.id_user_contract_person
),
pending_invoices_events AS (
  SELECT
    id_amplitude,
    id_session,
    ep_id_contracts,
    ep_id_invoices,
    device_brand,
    "pending_invoices_page_viewed" AS event_name,
    "Pending Invoice Page" AS funnel_step,
    ts_event
  FROM datalake_amplitude_clean.170698_pending_invoices_page_viewed_events

  UNION ALL

  SELECT
    id_amplitude,
    id_session,
    ep_id_contracts,
    ep_id_invoices,
    device_brand,
    "rm_pending_invoices_page_viewed" AS event_name,
    "Pending Invoice Page" AS funnel_step,
    ts_event
  FROM datalake_amplitude_clean.170698_rm_pending_invoices_page_viewed_events
),
explode_pending_invoices_events AS (
  SELECT
    id_contract,
    id_invoice,
    ep_id_contracts AS id_contracts,
    ep_id_invoices AS id_invoices,
    id_amplitude,
    id_session,
    device_brand,
    event_name,
    funnel_step,
    ts_event
  FROM pending_invoices_events
  LATERAL VIEW EXPLODE(from_json(ep_id_contracts, 'array<bigint>')) AS id_contract
  LATERAL VIEW EXPLODE(from_json(ep_id_invoices, 'array<string>')) AS id_invoice
),
union_all_events (
  SELECT
    id_amplitude,
    id_session,
    id_contract,
    NULL AS id_invoice,
    device_brand,
    "session_start" AS event_name,
    "Session Start" AS funnel_step,
    ts_event
  FROM get_session_start

  UNION ALL

  SELECT
    id_amplitude,
    id_session,
    ep_id_contract AS id_contract,
    NULL AS id_invoice,
    device_brand,
    "contract_page_viewed" AS event_name,
    "Contract Page" AS funnel_step,
    ts_event
  FROM datalake_amplitude_clean.170698_contract_page_viewed_events

  UNION ALL

  SELECT
    id_amplitude,
    id_session,
    id_contract,
    id_invoice,
    device_brand,
    event_name,
    funnel_step,
    ts_event
  FROM explode_pending_invoices_events

  UNION ALL

  SELECT
    id_amplitude,
    id_session,
    ep_id_contract AS id_contract,
    ep_id_invoice AS id_invoice,
    device_brand,
    "pending_invoices_invoice_pay_button_clicked" AS event_name,
    "Self Service Negotiation" AS funnel_step,
    ts_event
  FROM datalake_amplitude_clean.170698_pending_invoices_invoice_pay_button_clicked_events

  UNION ALL

  SELECT
    id_amplitude,
    id_session,
    ep_id_contract AS id_contract,
    ep_id_invoice AS id_invoice,
    device_brand,
    "rm_invoice_payment_option_clicked" AS event_name,
    "Self Service Negotiation" AS funnel_step,
    ts_event
  FROM datalake_amplitude_clean.170698_rm_invoice_payment_option_clicked_events
)
SELECT
  id_amplitude,
  id_session,
  BIGINT(id_contract) AS id_contract,
  BIGINT(id_invoice) AS id_invoice,
  device_brand,
  event_name,
  funnel_step,
  DATE_TRUNC("MONTH", ts_event) AS month_event,
  ts_event
FROM union_all_events
