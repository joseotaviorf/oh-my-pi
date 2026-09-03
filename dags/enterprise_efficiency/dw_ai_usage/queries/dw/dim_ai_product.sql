SELECT DISTINCT
    MD5(CONCAT_WS(',', tool, product)) AS sk_ai_product,
    tool,
    product
FROM
    datalake_ai_usage.usage_daily
WHERE
    product IS NOT NULL
