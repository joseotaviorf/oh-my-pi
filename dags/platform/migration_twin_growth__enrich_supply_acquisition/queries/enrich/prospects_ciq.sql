SELECT 
    ls.sk_supply_lead,
    hd.id_draft AS id_lead,
    hd.id_draft AS id_lead_ebdb,
    hd.id_region,
    hd.id_user_registrant,
    ls.source AS supply_source,
    hd.business_context,
    'conversion_l2p' AS business_event,
    'PROSPECT' AS funnel_step,
    2 AS funnel_level,
    hd.status AS aux_product_status,
    hd.city,
    hd.ts_created AS ts_event,
    CURRENT_TIMESTAMP() AS ts_load
FROM datalake_supply_flows.leads_sks AS ls
JOIN datalake_bob.house_draft_business_context AS hd
  ON (ls.id_lead = hd.id_draft)
    AND (ls.source = 'CIQ')
LEFT JOIN datalake_bob_clean.location AS l
  ON hd.id_draft = l.id_house_draft
WHERE hd.type IN ('ADMIN_CONFIRMATION', 'PORTFOLIO_MANAGER')
  AND (l.is_out_of_area IS NOT TRUE)
  AND (hd.status != 'DELETED')
  AND (hd.status != 'EDITING')
  AND DATE(hd.ts_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')  