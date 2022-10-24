WITH bu as (
    SELECT 
        `id`,
        negotiation_type,
        UPPER(hub_name) AS name,
        ROW_NUMBER () OVER ( PARTITION BY id ORDER BY ts_updated DESC) as row
    FROM 
        datalake_hub_services_clean.business_unit
    WHERE
        negotiation_type IN ('HUB', 'DEAL_MAKING', 'CLOSING_CENTRAL')
    )
SELECT
    `id`,
    negotiation_type,
    name,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day
FROM bu 
WHERE row = 1
ORDER BY 1
