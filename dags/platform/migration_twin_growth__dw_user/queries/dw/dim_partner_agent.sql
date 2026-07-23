SELECT  -- [ODS] This table was migrated from ODS flow and needs a future refactoring to remove castings and renamings
    pa.id AS sk_partner_agent,
    pa.id AS id_partner_agent,
    pa.id_user,
    pa.id_partner,
    COALESCE(u.country_code, 'Undefined') AS country_code,
    pa.status AS status_partner_agent,
    pa.type,
    pa.ts_created,
    pa.ts_updated,
    NOW() AS ts_load
FROM
    datalake_ebdb_clean.partner_agent AS pa
LEFT JOIN 
    datalake_ebdb_country.user AS u
        ON pa.id_user = u.id_user
