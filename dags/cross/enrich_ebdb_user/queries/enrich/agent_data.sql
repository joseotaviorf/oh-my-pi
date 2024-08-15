SELECT
    ad.id,
    ad.id_city,
    COALESCE(u.country_code, 'Undefined') AS country_code,
    ad.creci_number,
    ad.profile,
    ad.is_active,
    max(nullif(ad.creci_number, '') IS NOT NULL) AS is_realstate_agent,
    max(u.is_photographer) AS is_photographer,
    max(coalesce(adbc.business_context = 'SALE', false)) AS is_sale_agent,
    -- non existent agents on businessContextsServed table are assumed as RENT
    max(coalesce(adbc.business_context, 'RENT') = 'RENT') AS is_rent_agent,
    ad.ts_created,
    ad.ts_updated
FROM
    datalake_ebdb_clean.agent_data AS ad
LEFT JOIN
    datalake_ebdb_clean.agent_data_business_contexts_served adbc
        ON adbc.id_agent_data = ad.id
LEFT JOIN
    datalake_ebdb_user.user u
        ON u.id_agent = ad.id
GROUP BY 1, 2, 3, 4, 5, 6, 11, 12