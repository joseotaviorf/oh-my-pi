WITH
first_condo_monitoring_events AS (
  SELECT
    id_contract,
    MIN(ts_event) FILTER (WHERE source = 'COMMUNICATION' AND event_name = 'INVITE') AS ts_first_invitation,
    MIN(ts_event) FILTER (WHERE source = 'CONDO_MONITORING' AND event_name = 'ACTIVATED') AS ts_first_activation
  FROM
    datalake_condo_monitoring.condo_monitoring_events
  GROUP BY ALL
),
cm_non_payment_reports AS (
  SELECT
    e.id_contract,
    COUNT_IF(e.event_name = 'NON_PAYMENT_REPORT' AND e.ts_event < cme.ts_first_invitation) AS total_non_payment_report_before_first_invite,
    COUNT_IF(e.event_name = 'NON_PAYMENT_REPORT' AND e.ts_event > cme.ts_first_invitation) AS total_non_payment_report_after_first_invite,
    COUNT_IF(e.event_name = 'NON_PAYMENT_REPORT' AND e.ts_event < cme.ts_first_activation) AS total_non_payment_report_before_first_activation,
    COUNT_IF(e.event_name = 'NON_PAYMENT_REPORT' AND e.ts_event > cme.ts_first_activation) AS total_non_payment_report_after_first_activation,
    COUNT_IF(e.event_name = 'NON_PAYMENT_REPORT' AND e.was_condo_monitoring_active) AS total_non_payment_report_while_active,
    COUNT_IF(e.event_name = 'NON_PAYMENT_REPORT' AND NOT e.was_condo_monitoring_active) AS total_non_payment_report_while_inactive
  FROM
    datalake_condo_monitoring.condo_monitoring_events AS e
  JOIN
    first_condo_monitoring_events AS cme
      ON e.id_contract = cme.id_contract
  GROUP BY ALL
),
non_payment_reports AS (
  SELECT
    id_contract,
    COUNT(id) AS total_non_payment_report
  FROM
    datalake_condominium_payments_clean.non_payment_report
  WHERE
    expense_type = 'P'
  GROUP BY ALL
)
SELECT
  c.id AS sk_contract,
  c.id_proposal AS sk_proposal,
  hl.id_house_listing AS sk_house_listing,
  c.id_house AS sk_house,
  c.country_code,
  COUNT_IF(comm.communication_type = 'INVITE' AND comm.was_delivered) AS total_condo_monitoring_invite_sent,
  COALESCE(DATE_DIFF(DAY, cme.ts_first_invitation, cme.ts_first_activation), 0) AS days_to_activate_condo_monitoring,
  COALESCE(npr.total_non_payment_report, 0) AS total_non_payment_report,
  COALESCE(cm_npr.total_non_payment_report_before_first_invite, 0) AS total_non_payment_report_before_first_invite,
  COALESCE(cm_npr.total_non_payment_report_after_first_invite, 0) AS total_non_payment_report_after_first_invite,
  COALESCE(cm_npr.total_non_payment_report_before_first_activation, 0) AS total_non_payment_report_before_first_activation,
  COALESCE(cm_npr.total_non_payment_report_after_first_activation, 0) AS total_non_payment_report_after_first_activation,
  COALESCE(cm_npr.total_non_payment_report_while_active, 0) AS total_non_payment_report_while_active,
  COALESCE(cm_npr.total_non_payment_report_while_inactive, 0) AS total_non_payment_report_while_inactive,
  NOW() AS ts_load
FROM
  datalake_ebdb_contract.contract AS c
LEFT JOIN
  datalake_ebdb_listing.house_listing AS hl
    ON c.id = hl.id_contract
LEFT JOIN
  datalake_condo_monitoring.communication AS comm
    ON c.id = comm.id_contract
LEFT JOIN
  first_condo_monitoring_events AS cme
    ON c.id = cme.id_contract
LEFT JOIN
  cm_non_payment_reports AS cm_npr
    ON c.id = cm_npr.id_contract
LEFT JOIN
  non_payment_reports AS npr
    ON c.id = npr.id_contract
GROUP BY ALL
