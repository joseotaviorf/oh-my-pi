-- representation of the null value
SELECT
    MD5("N/A") AS sk_service_status,
    "N/A" AS service_status,
    NOW() AS ts_load
UNION ALL
SELECT DISTINCT
    MD5(service_status) AS sk_service_status,
    service_status,
    NOW() AS ts_load
FROM
    datalake_customer_support.chat
