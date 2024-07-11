WITH people_to_send AS (
  SELECT
    topd.customer_name,
    topd.customer_email,
    topd.customer_phone,
    topd.campaign_step,
    topd.customer_type,
    topd.customer_cpf,
    topd.id_user,
    topd.campaign_type,
    topd.driver_type,
    topd.id_driver
  FROM
    datalake_tracksale_dispatches.true_offboarding_pp_dispatches AS topd
  LEFT JOIN
    datalake_tracksale_dispatches.true_offboarding_pp_dispatches AS hist
      ON MAKE_DATE(hist.year, hist.month, hist.day) BETWEEN DATE_SUB(CURRENT_DATE(), 90) AND DATE_SUB(CURRENT_DATE(), 1)
      AND topd.id_driver = hist.id_driver
      AND topd.customer_email = hist.customer_email
      AND topd.customer_name = hist.customer_name
  WHERE
    MAKE_DATE(topd.year, topd.month, topd.day) = CURRENT_DATE()
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
  'Proprietário' AS customer_type,
  '1234' AS customer_cpf,
  '1234' AS id_user,
  'true' AS campaign_type,
  'contract' AS driver_type,
  '1234' AS id_driver
