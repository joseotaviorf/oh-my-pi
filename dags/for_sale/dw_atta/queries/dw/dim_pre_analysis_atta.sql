SELECT
    id_pre_analysis AS sk_pre_analysis,
    id_offer AS sk_offer,
    `status` AS sk_pre_analysis_status,
    priority_status AS sk_priority_status,
    situation AS sk_pre_analysis_situation,
    archive_reason,
    archive_complement,
    CASE
      WHEN created_source == 0 THEN 'iSolve'
      WHEN created_source == 1 THEN 'Partner Link'
      WHEN created_source == 2 THEN 'Buyer Offer Sent'
      WHEN created_source == 3 THEN 'Cash Converted'
      WHEN created_source == 4 THEN 'Recreated'
      ELSE created_source
    END AS created_source_description,
    down_payment_amount,
    financing_value,
    house_value,
    is_archived,
    ts_archived,
    ts_registration,
    NOW() AS ts_load
FROM
    datalake_atta_clean.pre_analysis
