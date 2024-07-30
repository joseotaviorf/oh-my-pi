SELECT
    p.id AS id_partner,
    paa.id_user,
    p.name,
    p.email,
    paa.status,
    CASE 
        WHEN ROW_NUMBER() OVER (PARTITION BY p.id ORDER BY ure.ts_revision DESC) = 1 THEN TRUE
        ELSE FALSE    
    END AS is_last_status,
    ure.ts_revision AS ts_agent_status_start,
    LEAD(ure.ts_revision) OVER (PARTITION BY p.id ORDER BY ure.ts_revision ASC) AS ts_agent_status_end
FROM
  datalake_ebdb_clean.partner AS p
LEFT JOIN 
  datalake_ebdb_clean.partner_agent_aud AS paa
    ON paa.id_partner = p.id
LEFT JOIN 
  datalake_ebdb_user.user_revision_entity AS ure
    ON paa.rev = ure.id
WHERE
  p.type = 'AUTONOMOUS_AGENT'