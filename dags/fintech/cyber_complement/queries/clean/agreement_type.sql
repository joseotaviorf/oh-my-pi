SELECT
  AGTYPE AS id_agreement_type,
  CASE
    WHEN AGACCTG = 1 THEN "QuintoAndar"
    WHEN AGACCTG = 2 THEN "QuintoCred"
    ELSE AGACCTG
  END AS contract_group,
  AGNAME AS agreement_type_description,
  AGCNDPAYN AS payments_to_be_forgiven,
  AGCNDPAYM AS fullfilled_payments_to_forgive,
  AGDMDAYSMIN AS min_delay_days,
  AGDMDAYSMAX AS max_delay_days,
  AGSORTORD AS order_classification,
  AGBREAK AS missed_payments_to_break_agreement,
  AGCSINITNT AS consecutive_payments_received,
  AGCSPERNT AS notify_central_system_periodically,
  AGPYTYPE AS payment_type,
  AGINITPYDAYS AS days_from_date_inicial_payment,
  AGINITPYMINP AS min_down_payment_percentage,
  AGINITPYMAXP AS max_percentage_initial_payment,
  AGLSTPYDAYS AS days_until_last_payment,
  AGRATE AS agreement_interest_rate,
  AGRATE2 AS fine_rate,
  AGGRDAYS As grace_period_days,
  AGMAXPMTS AS max_installments,
  AGFREQ AS valid_frequencies,
  AGINITDT AS ts_start_agreement,
  AGENDDT AS ts_end_agreement,
  AGMININITPY AS min_payment_amount,
  AGTAXRATE AS fees,
  AGVALPER AS valid_period,
  AGSELFCURE AS flag,
  AGSTATUS,
  AGMINPAR,
  AGCANALNEG AS agreement_channel,
  AGFORMAPAG AS payment_method,
  NOW() AS ts_load
FROM datalake_cyber_raw.agrtype
QUALIFY ROW_NUMBER() OVER(PARTITION BY AGTYPE ORDER BY ts_ingestion DESC) = 1
