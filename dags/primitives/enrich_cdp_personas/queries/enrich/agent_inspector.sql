SELECT
  u.id AS id_user,
  u.uuid_person,
  ad.is_active,
  COALESCE(ad.ts_created, ad.ts_updated) AS ts_first_event, -- Old users without creation date
  CASE
    WHEN ad.is_active = TRUE THEN CAST(NULL AS TIMESTAMP)
    ELSE ad.ts_updated
  END AS ts_last_event, -- As the agent source table is not updated frequently and is not event-based
  NOW() AS ts_load
FROM
    datalake_ebdb_clean.agent_data AS ad
JOIN
    datalake_ebdb_clean.agent_data_types AS b
        ON b.id_agent_data = ad.id
LEFT JOIN
    datalake_ebdb_clean.user AS u
        ON u.id_agent = ad.id
WHERE
    b.types IN ('Vistoria', 'VistoriaQuarteirizada')