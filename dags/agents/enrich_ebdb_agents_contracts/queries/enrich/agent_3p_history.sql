WITH agents_3p AS (
  SELECT DISTINCT
    id
  FROM
    datalake_ebdb_clean.agent_data_aud
  WHERE
    agent_type = 'CORRETOR_REDE'
)
SELECT
  ada.id AS id_agent,
  u.id AS id_user,
  ada.uuid_company,
  ada.agent_type,
  wc.contract_name,
  ROW_NUMBER() OVER (PARTITION BY ada.id ORDER BY ure.ts_revision) AS version,
  ada.agent_type = 'CORRETOR_REDE' AS is_3p_agent,
  ada.is_active,
  ada.is_passive_lead_receiver,
  ROW_NUMBER() OVER (PARTITION BY ada.id ORDER BY ure.ts_revision DESC) = 1 AS is_current,
  ada.rev_type = 2 AS is_deleted,
  ure.ts_revision AS ts_started,
  LEAD(ure.ts_revision) OVER (PARTITION BY ada.id ORDER BY ure.ts_revision) AS ts_ended
FROM
  datalake_ebdb_clean.agent_data_aud AS ada
JOIN
  agents_3p AS a3p
    ON ada.id = a3p.id
JOIN
  datalake_ebdb_user.user_revision_entity AS ure
    ON ure.id = ada.rev
LEFT JOIN
  datalake_ebdb_user.user AS u
    ON u.id_agent = ada.id
LEFT JOIN
  datalake_ebdb_clean.work_contract AS wc
    ON ada.id_work_contract = wc.id