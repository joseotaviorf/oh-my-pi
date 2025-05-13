WITH
overdue_invoices_events AS (
  SELECT
    id_amplitude,
    id_session,
    id_user,
    FROM_JSON(ep_id_contracts, 'array<bigint>') AS id_contract,
    FROM_JSON(ep_id_invoices, 'array<string>') AS id_invoice,
    device_family,
    "pending_invoices_page_viewed" AS event_name,
    "Overdue Self Service Viewed" AS funnel_step,
    3 AS level,
    "Triggers when user accesses the pending invoices page (overdue and upcoming)" AS event_description,
    FALSE AS is_active,
    year,
    month,
    day,
    ts_event
  FROM
    datalake_amplitude_clean.170698_pending_invoices_page_viewed_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

  UNION ALL

  SELECT
    id_amplitude,
    id_session,
    id_user,
    FROM_JSON(ep_id_contracts, 'array<bigint>') AS id_contract,
    FROM_JSON(ep_id_invoices, 'array<string>') AS id_invoice,
    device_family,
    "overdue_invoices_page_viewed" AS event_name,
    "Overdue Self Service Viewed" AS funnel_step,
    3 AS level,
    "Triggers when user accesses the overdue invoices page (new PWA flow)" AS event_description,
    TRUE AS is_active,
    year,
    month,
    day,
    ts_event
  FROM
    datalake_amplitude_clean.170698_overdue_invoices_page_viewed_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

  UNION ALL

  SELECT
    id_amplitude,
    id_session,
    id_user,
    FROM_JSON(ep_id_contracts, 'array<bigint>') AS id_contract,
    FROM_JSON(ep_id_invoices, 'array<string>') AS id_invoice,
    device_family,
    "overdue_invoices_invoice_pay_total_button_clicked" AS event_name,
    "Overdue Self Service Action" AS funnel_step,
    4 AS level,
    "Triggers when user accesses the the old PWA page for overdue invoices (new flow)" AS event_description,
    TRUE AS is_active,
    year,
    month,
    day,
    ts_event
  FROM
    datalake_amplitude_clean.170698_overdue_invoices_invoice_pay_total_button_clicked_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  ),
  explode_overdue_invoices_events AS (
  SELECT
    CAST(contract_invoice.id_contract AS BIGINT) AS id_contract,
    CAST(contract_invoice.id_invoice AS BIGINT) AS id_invoice,
    id_amplitude,
    id_session,
    id_user,
    device_family,
    event_name,
    funnel_step,
    level,
    event_description,
    is_active,
    year,
    month,
    day,
    ts_event
  FROM
    overdue_invoices_events
  LATERAL VIEW EXPLODE(
    ARRAYS_ZIP(
      id_contract,
      id_invoice
    )
  ) AS contract_invoice
  )

SELECT
  id_amplitude,
  id_session,
  id_user,
  CAST(ep_id_contract AS BIGINT) AS id_contract,
  CAST(NULL AS BIGINT) AS id_invoice,
  device_family,
  "contract_page_viewed" AS event_name,
  "Contract Page" AS funnel_step,
  1 AS level,
  "Triggers when user accesses the contract page under my rent" AS event_description,
  TRUE AS is_active,
  year,
  month,
  day,
  ts_event
FROM
  datalake_amplitude_clean.170698_contract_page_viewed_events
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

UNION ALL

SELECT
  id_amplitude,
  id_session,
  id_user,
  CAST(ep_id_contract AS BIGINT) AS id_contract,
  CAST(NULL AS BIGINT) AS id_invoice,
  device_family,
  "my_rent_pending_invoices_card_view" AS event_name,
  "Contract Page" AS funnel_step,
  2 AS level,
  "Triggers when user accesses the alert about overdue invoices on the 'My Rent' page" AS event_description,
  TRUE AS is_active,
  year,
  month,
  day,
  ts_event
FROM
  datalake_amplitude_clean.170698_my_rent_pending_invoices_card_view_events
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

UNION ALL

SELECT
  id_amplitude,
  id_session,
  id_user,
  CAST(id_contract AS BIGINT) AS id_contract,
  CAST(id_invoice AS BIGINT) AS id_invoice,
  device_family,
  event_name,
  funnel_step,
  level,
  event_description,
  is_active,
  year,
  month,
  day,
  ts_event
FROM explode_overdue_invoices_events

UNION ALL

SELECT
  id_amplitude,
  id_session,
  id_user,
  CAST(ep_id_contract AS BIGINT) AS id_contract,
  CAST(NULL AS BIGINT) AS id_invoice,
  device_family,
  "rm_pending_invoices_page_viewed" AS event_name,
  "Pending Invoices" AS funnel_step,
  3 AS level,
  "Triggers when user accesses the pending invoices page (overdue and upcoming)" AS event_description,
  TRUE AS is_active,
  year,
  month,
  day,
  ts_event
FROM
  datalake_amplitude_clean.170698_rm_pending_invoices_page_viewed_events
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

UNION ALL

SELECT
  id_amplitude,
  id_session,
  id_user,
  CAST(ep_id_contract AS BIGINT) AS id_contract,
  CAST(ep_id_invoice AS BIGINT) AS id_invoice,
  device_family,
  "pending_invoices_invoice_pay_button_clicked" AS event_name,
  "Overdue Self Service Action" AS funnel_step,
  4 AS level,
  "Triggers when user accesses the page to pay an individual pending invoice" AS event_description,
  FALSE AS is_active,
  year,
  month,
  day,
  ts_event
FROM
  datalake_amplitude_clean.170698_pending_invoices_invoice_pay_button_clicked_events
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

UNION ALL

SELECT
  id_amplitude,
  id_session,
  id_user,
  CAST(ep_id_contract AS BIGINT) AS id_contract,
  CAST(ep_id_invoice AS BIGINT) AS id_invoice,
  device_family,
  "overdue_invoices_invoice_pay_button_clicked" AS event_name,
  "Overdue Self Service Action" AS funnel_step,
  4 AS level,
  "Triggers when user accesses the page to pay an individual overdue invoice (new PWA flow)" AS event_description,
  TRUE AS is_active,
  year,
  month,
  day,
  ts_event
FROM
  datalake_amplitude_clean.170698_overdue_invoices_invoice_pay_button_clicked_events
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

UNION ALL

SELECT
  id_amplitude,
  id_session,
  id_user,
  CAST(ep_id_contract AS BIGINT) AS id_contract,
  CAST(NULL AS BIGINT) AS id_invoice,
  device_family,
  "pending_invoices_pay_total_cta_clicked" AS event_name,
  "Overdue Self Service Action" AS funnel_step,
  4 AS level,
  "Triggers when user accesses the page to negotiate the total amount from pending invoices" AS event_description,
  TRUE AS is_active,
  year,
  month,
  day,
  ts_event
FROM
  datalake_amplitude_clean.170698_pending_invoices_pay_total_cta_clicked_events
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

UNION ALL

SELECT
  id_amplitude,
  id_session,
  id_user,
  CAST(ep_id_contract AS BIGINT) AS id_contract,
  CAST(ep_id_invoice AS BIGINT) AS id_invoice,
  device_family,
  "rm_invoice_payment_option_clicked" AS event_name,
  "Pending Invoices" AS funnel_step,
  5 AS level,
  "Triggers when user accesses the page to choose the payment method for an individual pending invoice" AS event_description,
  TRUE AS is_active,
  year,
  month,
  day,
  ts_event
FROM
  datalake_amplitude_clean.170698_rm_invoice_payment_option_clicked_events
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

UNION ALL

SELECT
  id_amplitude,
  id_session,
  id_user,
  CAST(ep_id_contract AS BIGINT) AS id_contract,
  CAST(NULL AS BIGINT) AS id_invoice,
  device_family,
  "pending_invoices_payment_option_clicked" AS event_name,
  "Overdue Self Service Action" AS funnel_step,
  5 AS level,
  "Triggers when user accesses the page to choose the payment method for an individual pending invoice" AS event_description,
  TRUE AS is_active,
  year,
  month,
  day,
  ts_event
FROM
  datalake_amplitude_clean.170698_pending_invoices_payment_option_clicked_events
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

UNION ALL

SELECT
  id_amplitude,
  id_session,
  id_user,
  CAST(ep_id_contract AS BIGINT) AS id_contract,
  CAST(NULL AS BIGINT) AS id_invoice,
  device_family,
  "pi_negotiation_payment_option_clicked" AS event_name,
  "Overdue Self Service Action" AS funnel_step,
  5 AS level,
  "Triggers when user accesses the page to choose the payment method for all overdue invoices (new flow)" AS event_description,
  TRUE AS is_active,
  year,
  month,
  day,
  ts_event
FROM
  datalake_amplitude_clean.170698_pi_negotiation_payment_option_clicked_events
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
