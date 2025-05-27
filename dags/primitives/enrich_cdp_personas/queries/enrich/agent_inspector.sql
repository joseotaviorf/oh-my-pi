SELECT
  u.id AS id_user,
  u.uuid_person,
  ad.is_active,
  ad.ts_created AS ts_first_event,
  ad.ts_updated AS ts_last_event,
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