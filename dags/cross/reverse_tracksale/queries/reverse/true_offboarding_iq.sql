WITH people_to_send AS (
  SELECT
    toid.customer_name,
    toid.customer_email,
    toid.customer_phone,
    toid.campaign_step,
    toid.customer_type,
    toid.customer_cpf,
    toid.id_user,
    toid.campaign_type,
    toid.driver_type,
    toid.id_driver
  FROM
    datalake_tracksale_dispatches.true_offboarding_iq_dispatches AS toid
  LEFT JOIN
    datalake_tracksale_dispatches.true_offboarding_iq_dispatches AS hist
      ON MAKE_DATE(hist.year, hist.month, hist.day) BETWEEN DATE_SUB(CURRENT_DATE(), 90) AND DATE_SUB(CURRENT_DATE(), 1)
      AND toid.id_driver = hist.id_driver
      AND toid.customer_email = hist.customer_email
      AND toid.customer_name = hist.customer_name
  WHERE
    MAKE_DATE(toid.year, toid.month, toid.day) = CURRENT_DATE()
    AND hist.customer_email IS NULL
)
SELECT
  customer_name,
  customer_email,
  customer_phone,
  campaign_step,
  customer_type,
  customer_cpf,
  id_user,
  campaign_type,
  driver_type,
  id_driver
FROM
  people_to_send
UNION ALL
SELECT
  'Teste Disparo' AS customer_name,
  'testes.disparos.5a@gmail.com' AS customer_email,
  '+5511123456789' AS customer_phone,
  'Rescisão' AS campaign_step,
  'Inquilino' AS customer_type,
  '12345' AS customer_cpf,
  '12345' AS id_user,
  'true' AS campaign_type,
  'contract' AS driver_type,
  '12345' AS id_driver
