WITH
jaiminho AS (
  SELECT
    u.uuid_person,
    un.id AS id_communication,
    un.id_entity,
    BIGINT(REGEXP_EXTRACT(un.id_entity, '[-|_](.*?)[-|_]')) AS id_contract,
    BIGINT(REGEXP_EXTRACT(un.id_entity, '([^_-]+)$')) AS id_invoice,
    CASE
      WHEN entity_name = 'boletoMonitoringTenantBoletoNotPaidWarning' THEN 'WARNING'
      WHEN entity_name = 'boletoMonitoringTenantBoletoNotPaidD1' THEN 'REMINDER'
      WHEN entity_name = 'boletoMonitoringOwnerInvite' THEN 'INVITE'
    END AS communication_type,
    un.status,
    un.entity_name,
    un.status IN ('read', 'delivered') AS was_delivered,
    un.channel,
    un.ts_sent,
    DATE(REGEXP_EXTRACT(un.id_entity, r'(\d{{4}}-\d{{2}}-\d{{2}})')) AS dt_due,
    un.year,
    un.month,
    un.day
  FROM
    datalake_jaiminho_clean.user_notifications AS un
  LEFT JOIN
    datalake_ebdb_clean.user AS u
      ON un.id_user = u.id
  WHERE
    MAKE_DATE(un.year, un.month, un.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND un.entity_name IN (
      'boletoMonitoringTenantBoletoNotPaidD1',
      'boletoMonitoringTenantBoletoNotPaidWarning',
      'boletoMonitoringOwnerInvite'
    )
    AND un.status NOT IN ('failed')
)
  SELECT
    j.uuid_person,
    j.id_communication,
    j.id_entity,
    j.id_contract,
    IF(j.communication_type = 'INVITE', NULL, j.id_invoice) AS id_invoice,
    j.communication_type,
    j.status,
    j.entity_name,
    j.channel,
    j.was_delivered,
    CASE
      WHEN j.communication_type = 'INVITE' THEN NULL
      WHEN j.communication_type = 'WARNING' AND DATE(j.ts_sent) = DATE_ADD(COALESCE(j.dt_due, i.dt_due), 3) THEN TRUE
      WHEN j.communication_type = 'REMINDER' AND DATE(j.ts_sent) = DATE_ADD(COALESCE(j.dt_due, i.dt_due), -1) THEN TRUE
      ELSE FALSE
    END AS was_comm_sent_on_time,
    j.ts_sent,
    IF(j.communication_type = 'INVITE', NULL, COALESCE(j.dt_due, i.dt_due)) AS dt_due,
    j.year,
    j.month,
    j.day
  FROM
    jaiminho AS j
  LEFT JOIN
    datalake_condominium_payments_clean.invoice AS i
      ON j.id_invoice = i.id
