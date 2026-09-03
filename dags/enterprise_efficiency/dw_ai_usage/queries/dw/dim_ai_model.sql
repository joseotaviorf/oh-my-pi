SELECT DISTINCT
    MD5(CONCAT_WS(',', tool, model)) AS sk_ai_model,
    tool,
    model
FROM
    datalake_ai_usage.usage_daily
WHERE
    model IS NOT NULL
