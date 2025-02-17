WITH person_data AS (
  SELECT
    p.uuid_person,
    ci.id_person,
    p.person_name AS name,
    MAX(CASE WHEN ci.priority = 'PRIMARY' AND ci.category = 'EMAIL' THEN ci.contact_info END) AS primary_email,
    MAX(CASE WHEN ci.priority = 'SECONDARY' AND ci.category = 'EMAIL' THEN ci.contact_info END) AS secondary_email
  FROM
    datalake_person_clean.person as p
  LEFT JOIN
    datalake_person_clean.contact_info AS ci
      ON p.id = ci.id_person
  GROUP BY
    1,2,3 
)
SELECT
    p.id AS id_partner,
    p.uuid_company,
    u.uuid_person,
    paa.id_user,
    COALESCE(pd.name, p.name) AS name,
    COALESCE(pd.primary_email, pd.secondary_email, p.email) AS email,
    paa.status,
    CASE 
        WHEN ROW_NUMBER() OVER (PARTITION BY p.id ORDER BY ure.ts_revision DESC) = 1 THEN TRUE
        ELSE FALSE    
    END AS is_last_status,
    p.ts_created AS ts_agent_created,
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
LEFT JOIN
  datalake_ebdb_user.user AS u
    ON paa.id_user = u.id
LEFT JOIN
  person_data AS pd
    ON pd.uuid_person = u.uuid_person
WHERE
  p.type = 'AUTONOMOUS_AGENT'