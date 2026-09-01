SELECT
  CONCAT(
    CAST(bam.sk_broker AS STRING),
    bam.business_context,
    CAST(COALESCE(u.id, -1) AS STRING),
    CAST(bam.version AS STRING)
  ) AS sk_broker_account_manager_history,
  bam.sk_broker AS sk_broker,
  COALESCE(u.id, -1) AS sk_user_account_manager,
  ho.email AS account_manager,
  bam.business_context,
  bam.account_manager_source,
  bam.version,
  bam.is_current,
  TRUE AS has_3p_access_control,
  bam.ts_start,
  bam.ts_end,
  CURRENT_TIMESTAMP() AS ts_load,
  YEAR(bam.ts_start) AS year,
  MONTH(bam.ts_start) AS month,
  DAY(bam.ts_start) AS day
FROM
  datalake_brokers.broker_account_manager_history AS bam
LEFT JOIN
  datalake_hubspot.owner AS ho
    ON bam.id_account_manager = ho.id_owner
LEFT JOIN
  datalake_ebdb_user.user AS u
    ON ho.uuid_person = u.uuid_person
