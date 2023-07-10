SELECT
    id_pre_analysis      AS sk_pre_analysis,
    id_offer             AS sk_offer,
    `status`             AS sk_pre_analysis_status,
    priority_status      AS sk_priority_status,
    situation            AS sk_pre_analysis_situation,
    archive_reason,
    archive_complement,
    down_payment_amount,
    financing_value,
    house_value,
    is_archived,
    ts_archived,
    ts_registration,
    NOW()                AS ts_load
FROM
    datalake_atta_clean.pre_analysis
