WITH
pending_invoices_events AS (
  SELECT
    id_amplitude,
    id_session,
    id_user,
    FROM_JSON(ep_id_contracts, 'array<bigint>') AS id_contract,
    FROM_JSON(ep_id_invoices, 'array<string>') AS id_invoice,
    device_brand,
    "pending_invoices_page_viewed" AS event_name,
    "Pending Invoices" AS funnel_step,
    year,
    month,
    day,
    ts_event
  FROM datalake_amplitude_clean.170698_pending_invoices_page_viewed_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

  UNION ALL

  SELECT
    id_amplitude,
    id_session,
    id_user,
    FROM_JSON(ep_id_contracts, 'array<bigint>') AS id_contract,
    FROM_JSON(ep_id_invoices, 'array<string>') AS id_invoice,
    device_brand,
    "rm_pending_invoices_page_viewed" AS event_name,
    "Pending Invoices" AS funnel_step,
    year,
    month,
    day,
    ts_event
  FROM datalake_amplitude_clean.170698_rm_pending_invoices_page_viewed_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
explode_pending_invoices_events AS (
  SELECT
    contract_invoice.id_contract,
    contract_invoice.id_invoice,
    id_amplitude,
    id_session,
    id_user,
    device_brand,
    event_name,
    funnel_step,
    year,
    month,
    day,
    ts_event
  FROM pending_invoices_events
  LATERAL VIEW EXPLODE(
    ARRAYS_ZIP(
      id_contract,
      id_invoice
    )
  ) AS contract_invoice
),
union_all_events (
  SELECT
    id_amplitude,
    id_session,
    id_user,
    ep_id_contract AS id_contract,
    NULL AS id_invoice,
    device_brand,
    "contract_page_viewed" AS event_name,
    "Contract Page" AS funnel_step,
    "Triggers when user accesses the contract page under my rent" AS event_description,
    year,
    month,
    day,
    ts_event
  FROM datalake_amplitude_clean.170698_contract_page_viewed_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

  UNION ALL

  SELECT
    id_amplitude,
    id_session,
    id_user,
    ep_id_contract AS id_contract,
    NULL AS id_invoice,
    device_brand,
    "my_rent_pending_invoices_card_view" AS event_name,
    "My rent - Pending Invoices" AS funnel_step,
    "Triggers when user accesses the alert about overdue invoices on the 'My Rent' page" AS event_description,
    year,
    month,
    day,
    ts_event
  FROM datalake_amplitude_clean.170698_my_rent_pending_invoices_card_view_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

  UNION ALL

  SELECT
    id_amplitude,
    id_session,
    id_user,
    id_contract,
    id_invoice,
    device_brand,
    event_name,
    funnel_step,
    "Triggers when user accesses the pending invoices page (overdue and upcoming)" AS event_description,
    year,
    month,
    day,
    ts_event
  FROM explode_pending_invoices_events

  UNION ALL

  SELECT
    id_amplitude,
    id_session,
    id_user,
    ep_id_contract AS id_contract,
    ep_id_invoice AS id_invoice,
    device_brand,
    "pending_invoices_invoice_pay_button_clicked" AS event_name,
    "Self Service Negotiation" AS funnel_step,
    "Triggers when user accesses the page to pay de pending invoices" AS event_description,
    year,
    month,
    day,
    ts_event
  FROM datalake_amplitude_clean.170698_pending_invoices_invoice_pay_button_clicked_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

  UNION ALL

  SELECT
    id_amplitude,
    id_session,
    id_user,
    ep_id_contract AS id_contract,
    ep_id_invoice AS id_invoice,
    device_brand,
    "rm_invoice_payment_option_clicked" AS event_name,
    "Self Service Negotiation" AS funnel_step,
    "Triggers when user accesses the page to pay de pending invoices" AS event_description,
    year,
    month,
    day,
    ts_event
  FROM datalake_amplitude_clean.170698_rm_invoice_payment_option_clicked_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
  id_amplitude,
  id_session,
  id_user,
  BIGINT(id_contract) AS id_contract,
  BIGINT(id_invoice) AS id_invoice,
  device_brand,
  event_name,
  funnel_step,
  event_description,
  year,
  month,
  day,
  ts_event
FROM union_all_events
