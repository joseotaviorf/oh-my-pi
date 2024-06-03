SELECT 
    ls.sk_supply_lead,
    hd.id_draft AS id_lead,
    hd.id_draft AS id_lead_ebdb,
    hd.id_region,
    hd.id_user_registrant,
    ls.source AS supply_source,
    hd.business_context,
    'acquisition_tof2l' AS business_event,
    'LEAD' AS funnel_step,
    1 AS funnel_level,
    hd.status AS aux_product_status,
    hd.city, 
    hd.ts_created AS ts_event,
    CURRENT_TIMESTAMP() AS ts_load
FROM datalake_supply_flows.leads_sks AS ls
JOIN datalake_bob.house_draft_business_context AS hd
  ON (ls.id_lead = hd.id_draft)
    AND (hd.type = 'ADMIN_CONFIRMATION')
    AND (ls.source = 'CIQ')
WHERE DATE(hd.ts_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')