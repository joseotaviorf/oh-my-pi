WITH context_agent AS (
    /** Not all agents are present on the agent_data_business_contexts_served table.
        Based on that, agents not present should be considered as Rent context.
    **/
    SELECT
        ad.id,
        MAX(COALESCE(adbcs.business_context = 'SALE', FALSE)) AS is_sale_agent,
        MAX(COALESCE(adbcs.business_context = 'RENT', TRUE)) AS is_rent_agent
    FROM
        datalake_ebdb_clean.agent_data AS ad
    LEFT JOIN
        datalake_ebdb_clean.agent_data_business_contexts_served AS adbcs
            ON ad.id = adbcs.id_agent_data
    WHERE
        ad.is_active IS TRUE
    GROUP BY 1
)
SELECT DISTINCT
    DATE_FORMAT(DATE('{year}-{month}-{day}'), 'yyyyMMdd') AS id_snapshot,
    u.id AS id_user,
    u.id_country,
    'broker' AS client_type,
    COALESCE(ct.code, 'Undefined') AS country_code,
    u.main_phone,
    u.name,
    u.email,
    u.cpf,
    u.is_active,
    u.is_blocked,
    DATE(u.dt_birth) AS dt_birth,
    u.ts_created AS ts_user_created,
    u.ts_updated AS ts_user_updated,
    {year} AS year,
    {month} AS month,
    {day} AS day
FROM
    datalake_ebdb_clean.user AS u
INNER JOIN
    context_agent AS ca
        ON ca.id = u.id_agent
        AND (ca.is_sale_agent IS TRUE OR ca.is_rent_agent IS TRUE)
LEFT JOIN
    datalake_ebdb_clean.country AS ct
        ON ct.id = u.id_country
