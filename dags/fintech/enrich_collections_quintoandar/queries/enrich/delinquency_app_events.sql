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
    CAST(contract_invoice.filled_id_contract AS BIGINT) AS id_contract,
    CAST(contract_invoice.filled_id_invoice AS BIGINT) AS id_invoice,
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
    (
      SELECT
        *,
        CASE
          WHEN SIZE(id_contract) < SIZE(id_invoice) THEN
            CONCAT(id_contract, ARRAY_REPEAT(ELEMENT_AT(id_contract, -1), SIZE(id_invoice) - SIZE(id_contract)))
          ELSE id_contract
        END AS filled_id_contract,
        CASE
          WHEN SIZE(id_invoice) < SIZE(id_contract) THEN
            CONCAT(id_invoice, ARRAY_REPEAT(ELEMENT_AT(id_invoice, -1), SIZE(id_contract) - SIZE(id_invoice)))
          ELSE id_invoice
        END AS filled_id_invoice
      FROM overdue_invoices_events
    ) AS filled_arrays
  LATERAL VIEW EXPLODE(
    ARRAYS_ZIP(
      filled_id_contract,
      filled_id_invoice
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
  "Triggers when user accesses the page to negotiate the total amount from pending invoices (new flow)" AS event_description,
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
  CAST(NULL AS BIGINT) AS id_contract,
  CAST(NULL AS BIGINT) AS id_invoice,
  device_family,
  "pending_invoices_negotiation_cta_clicked" AS event_name,
  "Overdue Self Service Action" AS funnel_step,
  4 AS level,
  "Triggers when user accesses the page to negotiate the total amount from pending invoices" AS event_description,
  FALSE AS is_active,
  year,
  month,
  day,
  ts_event
FROM
  datalake_amplitude_clean.170698_pending_invoices_negotiation_cta_clicked_events
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
