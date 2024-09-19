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
  --Somente contratos com dias de atraso* maior ou igual a 8 e menor ou igual a 60 estarão disponíveis para esse tipo de acordo.
  AGDMDAYSMIN AS min_delay_days, --Dias de atraso mínimo que deve ter o contrato para que possa estar disponível para esse tipo de acordo
  AGDMDAYSMAX AS max_delay_days, -- Dias de atraso máximo que deve ter o contrato para que possa estar disponível para esse tipo de acordo
  AGSORTORD AS order_classification, --É a ordem de classificação do acordo. Existe um acordo padrão e sempre tem que ser apresentado como o primeiro na tela do CyberAgreements.
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
  AGGRDAYS As free_days,
  AGMAXPMTS AS max_installments, --Número máximo de parcelas permitidas.
  AGFREQ AS valid_frequencies,
  AGINITDT AS ts_start_agreement,
  AGENDDT AS ts_end_agreement,
  AGMININITPY AS min_payment_amount,
  AGTAXRATE AS fees,
  AGVALPER AS valid_period,
  AGSELFCURE AS flag,
  AGSTATUS,
  AGMINPAR,
  AGCANALNEG AS agreement_channel, --Verificar definições existentes na estória de Multicanalidade.
  AGFORMAPAG AS payment_method -- BOL = boleto, CAR =Cartão de crédito, DCO = débito em conta.
FROM datalake_cyber_raw.agrtype
