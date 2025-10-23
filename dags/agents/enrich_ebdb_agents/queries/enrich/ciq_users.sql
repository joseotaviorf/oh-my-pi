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
),
df_partners AS (

  SELECT
    p.id AS id_partner,
    ure.id AS rev,
    p.uuid_company,
    u.uuid_person,
    paa.id_user,
    m.id_winner_account AS id_user_winner_account,
    COALESCE(pd.name, p.name) AS name,
    COALESCE(pd.primary_email, pd.secondary_email, p.email) AS email,
    paa.status,
    IFNULL(paa.status = 'ACTIVE', false) AS is_active,
    m.id_loser_account IS NOT NULL AS is_merge_loser_account,
    ROW_NUMBER() OVER (PARTITION BY p.id, paa.id_user ORDER BY ure.ts_revision DESC) = 1 AS is_user_last_status,
    (fu.id_user IS NOT NULL OR m.id_loser_account IS NULL) AS is_last_valid_user,
    p.ts_created AS ts_agent_created,
    m.ts_created AS ts_user_merged,
    ure.ts_revision AS ts_agent_status_start,
    LEAD(ure.ts_revision) OVER (PARTITION BY p.id, paa.id_user ORDER BY ure.ts_revision ASC) AS ts_agent_status_end
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
  LEFT JOIN
    datalake_ebdb_clean.user_merge AS m
        ON m.id_loser_account = paa.id_user
            AND m.status = 'MERGED'
  LEFT JOIN
    datalake_ebdb_user.user_merge AS fu
        ON fu.id_user = paa.id_user
  WHERE
    p.type = 'AUTONOMOUS_AGENT'
    AND ENDSWITH(COALESCE(pd.primary_email, pd.secondary_email, p.email), '@quintoandar.com.br') = FALSE

)
 SELECT
    id_partner,
    id_user,
    uuid_company,
    uuid_person,
    name,
    email,
    status,
    is_active,
    is_merge_loser_account,
    CASE
      WHEN
        SUM(CASE WHEN is_last_valid_user = TRUE AND is_user_last_status = TRUE THEN 1 END) OVER(PARTITION BY id_partner) > 1
            AND is_last_valid_user = true
            AND is_user_last_status = true
      THEN ROW_NUMBER() OVER(PARTITION BY id_partner ORDER BY ts_agent_status_start DESC) = 1
      WHEN
        SUM(CASE WHEN is_last_valid_user = TRUE AND is_user_last_status = TRUE THEN 1 END) OVER(PARTITION BY id_partner) = 1
            AND is_last_valid_user = true
            AND is_user_last_status = true
      THEN TRUE
      ELSE FALSE
    END AS is_last_status,
    ts_agent_created,
    ts_agent_status_start,
    ts_agent_status_end
 FROM
    df_partners
