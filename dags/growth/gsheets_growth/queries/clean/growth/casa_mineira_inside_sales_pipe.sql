SELECT
    CAST(id_pipe AS INTEGER) AS id_pipe,
    consultor,
    entry_channel,
    status,
    CASE
        WHEN ts_lead IS NOT NULL AND ts_lead <> '-' THEN TIMESTAMP(ts_lead)
        ELSE NULL
    END AS ts_lead
FROM
    datalake_gsheets_raw.casa_mineira_inside_sales_pipe