SELECT
    pa.id_user,
    u.uuid_person,
    IF(pa.status = 'ACTIVE', TRUE, FALSE) AS is_active,
    pa.ts_created AS ts_first_event,
    pa.ts_updated AS ts_last_event,
    NOW() AS ts_load
FROM
    datalake_ebdb_clean.partner AS p
JOIN
    datalake_ebdb_clean.partner_agent AS pa
        ON pa.id_partner = p.id
LEFT JOIN
    datalake_ebdb_clean.user AS u
        ON u.id = pa.id_user
WHERE
    p.type = 'AUTONOMOUS_AGENT' -- CIQ and ASP
    AND ENDSWITH(p.email, '@quintoandar.com.br') = FALSE -- CIQ agent has email outside quintoandar domain