SELECT  -- [ODS] This table was migrated from ODS flow and needs a future refactoring to remove castings and renamings
    id AS sk_partner_agent,
    id AS id_partner_agent,
    id_user,
    id_partner,
    status AS status_partner_agent,
    type,
    ts_created,
    ts_updated,
    NOW() AS ts_load
FROM datalake_ebdb_clean.partner_agent
