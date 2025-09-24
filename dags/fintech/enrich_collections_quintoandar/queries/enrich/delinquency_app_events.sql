WITH
overdue_invoices_events AS (
  SELECT
    id_amplitude,
    id_session,
    id_user,
    ARRAY(ep_id_contract) AS id_contract,
    FROM_JSON(ep_id_invoices, 'array<string>') AS id_invoice,
    device_family,
    "rm_pending_invoices_page_viewed" AS event_name,
    event_properties,
    "Pending Invoices" AS funnel_step,
    3 AS level,
    "Triggers when user views the pending invoices page (overdue and upcoming)" AS event_description,
    "pix_cc" AS feature,
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
    FROM_JSON(ep_id_contracts, 'array<bigint>') AS id_contract,
    FROM_JSON(ep_id_invoices, 'array<string>') AS id_invoice,
    device_family,
    "pending_invoices_page_viewed" AS event_name,
    event_properties,
    "Pending Invoices" AS funnel_step,
    3 AS level,
    "Triggers when user views the old pending invoices page (overdue and upcoming)" AS event_description,
    "pwa" AS feature,
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
    event_properties,
    "Overdue Invoices" AS funnel_step,
    3 AS level,
    "Triggers when user views the old overdue invoices page" AS event_description,
    "pwa" AS feature,
    FALSE AS is_active,
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
    event_properties,
    "Overdue Self Service Action" AS funnel_step,
    4 AS level,
    "Triggers when user clicks the 'Pagar total' button on the 'Overdue Invoices' page" AS event_description,
    "pwa" AS feature,
    FALSE AS is_active,
    year,
    month,
    day,
    ts_event
  FROM
    datalake_amplitude_clean.170698_overdue_invoices_invoice_pay_total_button_clicked_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

  UNION ALL

  SELECT
    id_amplitude,
    id_session,
    id_user,
    CAST(ep_id_contract AS BIGINT) AS id_contract,
    FROM_JSON(ep_id_invoices, 'array<string>') AS id_invoice,
    device_family,
    "pending_invoices_pay_total_cta_clicked" AS event_name,
    event_properties,
    "Overdue Self Service Action" AS funnel_step,
    4 AS level,
    "Triggers when user clicks the 'Pagar total' button on the 'Faturas em atraso' card on the 'Pending Invoices' page" AS event_description,
    "pix_cc" AS feature,
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
    ARRAY(ep_id_contract) AS id_contract,
    FROM_JSON(ep_id_invoices, 'array<string>') AS id_invoice,
    device_family,
    "coll_review_check_negotiation_page_onload" AS event_name,
    event_properties,
    "Overdue Self Service Action" AS funnel_step,
    5 AS level,
    "Triggers when user views the 'Review Amounts' page" AS event_description,
    "pix_cc" AS feature,
    TRUE AS is_active,
    year,
    month,
    day,
    ts_event
  FROM
    datalake_amplitude_clean.170698_coll_review_check_negotiation_page_onload_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

  UNION ALL

  SELECT
    id_amplitude,
    id_session,
    id_user,
    ARRAY(ep_id_contract) AS id_contract,
    FROM_JSON(ep_id_invoices, 'array<string>') AS id_invoice,
    device_family,
    "overdue_invoices_total_payment_option_viewed" AS event_name,
    event_properties,
    "Overdue Self Service Action" AS funnel_step,
    7 AS level,
    "Triggers when user views the 'Pagar total' page with boleto, pix, and credit card options (Payment of Original)" AS event_description,
    "pix_cc" AS feature,
    TRUE AS is_active,
    year,
    month,
    day,
    ts_event
  FROM
    datalake_amplitude_clean.170698_overdue_invoices_total_payment_option_viewed_events
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
    "overdue_invoices_total_payment_option_clicked" AS event_name,
    event_properties,
    "Overdue Self Service Action" AS funnel_step,
    8 AS level,
    "Triggers when user clicks one of the invoice payment options on the 'Pagar fatura' page" AS event_description,
    "pwa" AS feature,
    TRUE AS is_active,
    year,
    month,
    day,
    ts_event
  FROM
    datalake_amplitude_clean.170698_overdue_invoices_total_payment_option_clicked_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

  UNION ALL

  SELECT
    id_amplitude,
    id_session,
    id_user,
    ARRAY(ep_id_contract) AS id_contract,
    FROM_JSON(ep_id_invoices, 'array<string>') AS id_invoice,
    device_family,
    "coll_review_check_negotiation_cta_onclick" AS event_name,
    event_properties,
    "Overdue Self Service Action" AS funnel_step,
    6 AS level,
    "Triggers when user clicks the 'Escolher como pagar' button on the 'Revisar valores' page" AS event_description,
    "pix_cc" AS feature,
    TRUE AS is_active,
    year,
    month,
    day,
    ts_event
  FROM
    datalake_amplitude_clean.170698_coll_review_check_negotiation_cta_onclick_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

  UNION ALL

  SELECT
    id_amplitude,
    id_session,
    id_user,
    ARRAY(ep_id_contract) AS id_contract,
    FROM_JSON(ep_id_invoices, 'array<string>') AS id_invoice,
    device_family,
    "coll_negotiation_menu_page_onload" AS event_name,
    event_properties,
    "Overdue Self Service Action" AS funnel_step,
    7 AS level,
    "Triggers when user views the 'Escolher como pagar' button on the 'Revisar valores' page" AS event_description,
    "pix_cc" AS feature,
    TRUE AS is_active,
    year,
    month,
    day,
    ts_event
  FROM
    datalake_amplitude_clean.170698_coll_negotiation_menu_page_onload_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

  UNION ALL

  SELECT
    id_amplitude,
    id_session,
    id_user,
    ARRAY(ep_id_contract) AS id_contract,
    FROM_JSON(ep_id_invoices, 'array<string>') AS id_invoice,
    device_family,
    "coll_negotiation_menu_page_payment_option_select_onclick" AS event_name,
    event_properties,
    "Overdue Self Service Action" AS funnel_step,
    8 AS level,
    "Triggers when user selects the payment method (boleto, pix, or credit card) on the 'Como gostaria de pagar?' page" AS event_description,
    "pix_cc" AS feature,
    TRUE AS is_active,
    year,
    month,
    day,
    ts_event
  FROM
    datalake_amplitude_clean.170698_coll_negotiation_menu_page_payment_option_select_onclick_events
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

  UNION ALL

  SELECT
    id_amplitude,
    id_session,
    id_user,
    ARRAY(ep_id_contract) AS id_contract,
    FROM_JSON(ep_id_invoices, 'array<string>') AS id_invoice,
    device_family,
    "coll_negotiation_menu_page_payment_cta_onclick" AS event_name,
    event_properties,
    "Overdue Self Service Action" AS funnel_step,
    9 AS level,
    "Triggers when user clicks the button 'Pagar fatura' on the 'Como gostaria de pagar?' page" AS event_description,
    "pix_cc" AS feature,
    TRUE AS is_active,
    year,
    month,
    day,
    ts_event
  FROM
    datalake_amplitude_clean.170698_coll_negotiation_menu_page_payment_cta_onclick_events
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
    event_properties,
    funnel_step,
    level,
    event_description,
    feature,
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
    ARRAYS_ZIP(filled_id_contract, filled_id_invoice)
  ) AS contract_invoice


  UNION ALL

  SELECT
    CAST(contract_val AS BIGINT) AS id_contract,
    CAST(NULL AS BIGINT) AS id_invoice,
    id_amplitude,
    id_session,
    id_user,
    device_family,
    event_name,
    event_properties,
    funnel_step,
    level,
    event_description,
    feature,
    is_active,
    year,
    month,
    day,
    ts_event
  FROM overdue_invoices_events
  LATERAL VIEW EXPLODE(id_contract) AS contract_val
  WHERE COALESCE(ARRAY_JOIN(id_invoice, ','), '') = '' OR COALESCE(ARRAY_JOIN(id_invoice, ','), '') = 'null'

  UNION ALL

  SELECT
    CAST(NULL AS BIGINT) AS id_contract,
    CAST(invoice_val AS BIGINT) AS id_invoice,
    id_amplitude,
    id_session,
    id_user,
    device_family,
    event_name,
    event_properties,
    funnel_step,
    level,
    event_description,
    feature,
    is_active,
    year,
    month,
    day,
    ts_event
  FROM overdue_invoices_events
  LATERAL VIEW EXPLODE(id_invoice) AS invoice_val
  WHERE COALESCE(ARRAY_JOIN(id_contract, ','), '') = '' OR COALESCE(ARRAY_JOIN(id_contract, ','), '') = 'null'
  )

SELECT
  id_amplitude,
  id_session,
  id_user,
  CAST(id_contract AS BIGINT) AS id_contract,
  CAST(id_invoice AS BIGINT) AS id_invoice,
  device_family,
  event_name,
  event_properties,
  funnel_step,
  level,
  event_description,
  feature,
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
  "my_rent_pending_invoices_card_view" AS event_name,
  event_properties,
  "Contract Page" AS funnel_step,
  1 AS level,
  "Triggers when user views the Critical Banner on the 'My Rent' page" AS event_description,
  "pix_cc" AS feature,
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
  CAST(ep_id_contract AS BIGINT) AS id_contract,
  CAST(NULL AS BIGINT) AS id_invoice,
  device_family,
  "contract_page_viewed" AS event_name,
  event_properties,
  "Contract Page" AS funnel_step,
  2 AS level,
  "Triggers when user views the contract page under my rent" AS event_description,
  "pix_cc" AS feature,
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
  CAST(ep_id_invoice AS BIGINT) AS id_invoice,
  device_family,
  "overdue_invoices_invoice_pay_button_clicked" AS event_name,
  event_properties,
  "Overdue Self Service Action" AS funnel_step,
  4 AS level,
  "Triggers when user clicks the 'Pagar fatura' button on the 'Overdue Invoices' page" AS event_description,
  "pwa" AS feature,
  FALSE AS is_active,
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
  "my_rent_pending_invoices_card_view" AS event_name,
  event_properties,
  "Overdue Self Service Action" AS funnel_step,
  4 AS level,
  "Triggers when user clicks the 'Pagar fatura' button on the 'Pending Invoices' page" AS event_description,
  "pwa" AS feature,
  TRUE AS is_active,
  year,
  month,
  day,
  ts_event
FROM
  datalake_amplitude_clean.170698_pending_invoices_pay_invoice_cta_clicked_events
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
  event_properties,
  "Overdue Self Service Action" AS funnel_step,
  4 AS level,
  "Triggers when user clicks the 'Pagar fatura' button on the 'Pending Invoices' page" AS event_description,
  "pwa" AS feature,
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
  CAST(NULL AS BIGINT) AS id_contract,
  CAST(NULL AS BIGINT) AS id_invoice,
  device_family,
  "pending_invoices_negotiation_cta_clicked" AS event_name,
  event_properties,
  "Overdue Self Service Action" AS funnel_step,
  4 AS level,
  "Triggers when user clicks the 'Pagar total' button on the 'Pending Invoices' page" AS event_description,
  "pwa" AS feature,
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
  ep_id_contract AS id_contract,
  CAST(NULL AS BIGINT) AS id_invoice,
  device_family,
  "overdue_invoices_payment_option_viewed" AS event_name,
  event_properties,
  "Overdue Self Service Action" AS funnel_step,
  7 AS level,
  "Triggers when user views the drawer with boleto, pix, and credit card options (Payment of Original)" AS event_description,
  "pix_cc" AS feature,
  TRUE AS is_active,
  year,
  month,
  day,
  ts_event
FROM
  datalake_amplitude_clean.170698_overdue_invoices_payment_option_viewed_events
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')

UNION ALL

SELECT
  id_amplitude,
  id_session,
  id_user,
  ep_id_contract AS id_contract,
  CAST(NULL AS BIGINT) AS id_invoice,
  device_family,
  "overdue_invoices_payment_options_closed" AS event_name,
  event_properties,
  "Overdue Self Service Dropout" AS funnel_step,
  8 AS level,
  "Triggers when user clicks the button to close the 'Pagar fatura' page or the 'Pagar total' button (Payment of Original)" AS event_description,
  "pix_cc" AS feature,
  TRUE AS is_active,
  year,
  month,
  day,
  ts_event
FROM
  datalake_amplitude_clean.170698_overdue_invoices_payment_options_closed_events
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
  event_properties,
  "Overdue Self Service Action" AS funnel_step,
  8 AS level,
  "Triggers when user clicks one of the invoice payment options in the payment drawer (Payment of Original)" AS event_description,
  "pix_cc" AS feature,
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
  "overdue_invoices_payment_option_clicked" AS event_name,
  event_properties,
  "Overdue Self Service Action" AS funnel_step,
  8 AS level,
  "Triggers when user clicks one of the invoice payment options on the 'Pagar fatura' page (Payment of Original)" AS event_description,
  "pix_cc" AS feature,
  TRUE AS is_active,
  year,
  month,
  day,
  ts_event
FROM
  datalake_amplitude_clean.170698_overdue_invoices_payment_option_clicked_events
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
  "pi_negotiation_started_page_viewed" AS event_name,
  event_properties,
  "Overdue Self Service Action" AS funnel_step,
  10 AS level,
  "Triggers when user views the payment page" AS event_description,
  "pix_cc" AS feature,
  TRUE AS is_active,
  year,
  month,
  day,
  ts_event
FROM
  datalake_amplitude_clean.170698_pi_negotiation_started_page_viewed_events
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
  event_properties,
  "Overdue Self Service Action" AS funnel_step,
  11 AS level,
  "Triggers when user views the payment page" AS event_description,
  "pix_cc" AS feature,
  TRUE AS is_active,
  year,
  month,
  day,
  ts_event
FROM
  datalake_amplitude_clean.170698_pi_negotiation_payment_option_clicked_events
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
  "pi_negotiation_payment_option_closed" AS event_name,
  event_properties,
  "Overdue Self Service Dropout" AS funnel_step,
  11 AS level,
  "Triggers when user closes the payment page" AS event_description,
  "pix_cc" AS feature,
  TRUE AS is_active,
  year,
  month,
  day,
  ts_event
FROM
  datalake_amplitude_clean.170698_pi_negotiation_payment_option_closed_events
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
  "pending_invoices_exception_page_viewed" AS event_name,
  event_properties,
  "Overdue Self Service Dropout" AS funnel_step,
  10 AS level,
  "Triggers when user views the error page in the payment process" AS event_description,
  "pix_cc" AS feature,
  TRUE AS is_active,
  year,
  month,
  day,
  ts_event
FROM
  datalake_amplitude_clean.170698_pending_invoices_exception_page_viewed_events
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
  "pending_invoices_exception_page_viewed" AS event_name,
  event_properties,
  "Overdue Self Service Dropout" AS funnel_step,
  7 AS level,
  "Triggers when user views the error page in the payment process" AS event_description,
  "pix_cc" AS feature,
  TRUE AS is_active,
  year,
  month,
  day,
  ts_event
FROM
  datalake_amplitude_clean.170698_pending_invoices_exception_page_viewed_events
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
  "pending_invoices_exception_cta_clicked" AS event_name,
  event_properties,
  "Overdue Self Service Action" AS funnel_step,
  11 AS level,
  "Triggers when user clicks the 'Regularizar com suporte' button on the error page in the payment process" AS event_description,
  "pix_cc" AS feature,
  TRUE AS is_active,
  year,
  month,
  day,
  ts_event
FROM
  datalake_amplitude_clean.170698_pending_invoices_exception_cta_clicked_events
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
  "checkout_order_credit_card_payment_button_tapped" AS event_name,
  event_properties,
  "Overdue Self Service Action" AS funnel_step,
  12 AS level,
  "Triggers when user clicks the Credit Card payment button on the Checkout page" AS event_description,
  "checkout" AS feature,
  TRUE AS is_active,
  year,
  month,
  day,
  ts_event
FROM
  datalake_amplitude_clean.170698_checkout_order_credit_card_payment_button_tapped_events
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
  "checkout_order_credit_card_payment_success_view" AS event_name,
  event_properties,
  "Overdue Self Service Action" AS funnel_step,
  12 AS level,
  "Triggers when the Credit Card payment is successfull" AS event_description,
  "checkout" AS feature,
  TRUE AS is_active,
  year,
  month,
  day,
  ts_event
FROM
  datalake_amplitude_clean.170698_checkout_order_credit_card_payment_success_view_events
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
  "checkout_order_credit_card_payment_failure_view" AS event_name,
  event_properties,
  "Overdue Self Service Dropout" AS funnel_step,
  12 AS level,
  "Triggers when the Credit Card payment fails" AS event_description,
  "checkout" AS feature,
  TRUE AS is_active,
  year,
  month,
  day,
  ts_event
FROM
  datalake_amplitude_clean.170698_checkout_order_credit_card_payment_failure_view_events
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
  "checkout_order_credit_card_payment_pending_view" AS event_name,
  event_properties,
  "Overdue Self Service Dropout" AS funnel_step,
  12 AS level,
  "Triggers when the Credit Card payment is pending" AS event_description,
  "checkout" AS feature,
  TRUE AS is_active,
  year,
  month,
  day,
  ts_event
FROM
  datalake_amplitude_clean.170698_checkout_order_credit_card_payment_pending_view_events
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
  "checkout_order_credit_card_try_again_tapped" AS event_name,
  event_properties,
  "Overdue Self Service Dropout" AS funnel_step,
  12 AS level,
  "Triggers when the user clicks the button 'Tentar Novamente' on the Credit Card payment failure page" AS event_description,
  "checkout" AS feature,
  TRUE AS is_active,
  year,
  month,
  day,
  ts_event
FROM
  datalake_amplitude_clean.170698_checkout_order_credit_card_try_again_tapped_events
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
