SELECT
    reason,
    reason_category,
    new_reason,
    responsible,
    CAST(count AS INTEGER) AS count
FROM
    datalake_gsheets_raw.de_para_cancelamento