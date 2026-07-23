SELECT
  MD5(
    CONCAT(
      id_user,
      event_type,
      CAST(ts_event AS STRING)
    )
  ) AS sk_event,
  id_user AS sk_user,
  CASE
    WHEN event_type = 'ongoing_requests_timeline_page_viewed' THEN 'ONGOING REQUESTS'
    WHEN event_type = 'faq_article_page_viewed' THEN 'FAQ'
    WHEN event_type IN ('owner_income_tax_shortcut_tapped', 'owner_urban_property_tax_shortcut_tapped')
      THEN 'SHORTCUT CENTER SEASONAL'
    WHEN event_type IN (
      'help_center_pre_triage_new_subject_clicked',
      'help_center_pre_triage_direct_routing_option_clicked',
      'help_center_pre_triage_page_viewed',
      'help_center_pre_triage_page_closed',
      'help_center_triage_option_clicked',
      'help_center_main_triage_page_closed',
      'help_center_sub_triage_page_closed',
      'help_center_triage_channel_offer_chosen',
      'help_center_call_cancelled',
      'help_center_call_exchanged_for_chat',
      'chat_menu_item_clicked',
      'help_center_call_channel_drawer_button_confirm',
      'help_center_call_channel_drawer_button_back'
    ) THEN 'CALL IN APP'
    WHEN event_type LIKE 'kb_hs%' OR event_type LIKE 'kb_ss%' THEN 'KNOWLEDGE BASE'
    ELSE 'SHORTCUT CENTER'
  END AS event_from,
  event_properties,
  event_type,
  CASE
    WHEN id_app = 170698 THEN 'TENANT APP'
    WHEN id_app = 183047 THEN 'LANDLORD APP'
    ELSE 'OTHER'
  END AS app,
  city,
  region,
  country,
  device_carrier,
  device_family,
  device_type,
  os_name,
  os_version,
  version_name,
  ts_event,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_amplitude_clean.events
WHERE
  MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
  AND id_user NOT IN ('false', 'userId')
  AND id_user IS NOT NULL
  AND (
    (
      id_app IN (170135, 370096)
      AND event_type LIKE ANY (
        '%kb_ss%',
        '%kb_hs%'
      ) 
    ) OR (
      id_app IN (170698, 183047)
      AND event_type IN (
        'help_center_page_viewed',
        'faq_article_page_viewed',
        'ongoing_requests_timeline_page_viewed',
        'tenant_repair_request_shortcut_tapped',
        'tenant_simulate_termination_fee_shortcut_tapped',
        'tenant_termination_request_shortcut_tapped',
        'last_invoice_shortcut_tapped',
        'tenant_refund_request_shortcut_tapped',
        'tenant_termination_management_shortcut_tapped',
        'request_sign_shortcut_tapped',
        'request_new_photos_shortcut_tapped',
        'request_lockbox_shortcut_tapped',
        'owners_how_to_improve_ad_shortcut_tapped',
        'owners_visit_schedule_shortcut_tapped',
        'owners_edit_ad_shortcut_tapped',
        'owner_send_documents_shortcut_tapped',
        'owner_report_non_payment_shortcut_tapped',
        'owner_inspection_report_shortcut_tapped',
        'menu_transfers_shortcut_tapped',
        'owner_income_tax_shortcut_tapped',
        'owner_urban_property_tax_shortcut_tapped'
        'help_center_pre_triage_new_subject_clicked',
        'help_center_pre_triage_direct_routing_option_clicked',
        'help_center_pre_triage_page_viewed',
        'help_center_pre_triage_page_closed',
        'help_center_triage_option_clicked',
        'help_center_main_triage_page_closed',
        'help_center_sub_triage_page_closed',
        'help_center_triage_channel_offer_chosen',
        'help_center_call_cancelled',
        'help_center_call_exchanged_for_chat',
        'chat_menu_item_clicked',
        'help_center_call_channel_drawer_button_confirm',
        'help_center_call_channel_drawer_button_back'
      )
    )
  )