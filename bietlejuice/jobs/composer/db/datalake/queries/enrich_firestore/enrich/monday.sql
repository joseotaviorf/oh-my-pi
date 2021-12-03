WITH last_update AS (
SELECT
    GET_JSON_OBJECT(updated_message, '$.offerId') AS id,
    MAX(ts_updated) AS ts_last_updated
FROM datalake_firestore_clean.monday
GROUP BY 1
),
monday AS (
SELECT
  moa.id,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.texto90.value') AS BIGINT) AS id_buyer,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.texto1.value') AS BIGINT) AS id_house,
  CAST(REGEXP_EXTRACT(GET_JSON_OBJECT(moa.updated_message, '$.pessoas1.value'), '(\\w+)') AS BIGINT) AS id_closing_specialist,
  GET_JSON_OBJECT(moa.updated_message, '$.pessoas.value') AS id_consultant,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.text1.value') AS BIGINT) AS id_agent,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.text5.value') AS BIGINT) AS id_fifty_agent,
  CAST(REGEXP_EXTRACT(GET_JSON_OBJECT(moa.updated_message, '$.pessoas0.value'), '(\\w+)') AS BIGINT) AS id_legal_risk_analyst,
  CAST(REGEXP_EXTRACT(GET_JSON_OBJECT(moa.updated_message, '$.pessoas1.value'), '(\\w+)') AS BIGINT) AS id_pre_specialist,
  CAST(REGEXP_EXTRACT(GET_JSON_OBJECT(moa.updated_message, '$.pessoas2.value'), '(\\w+)') AS BIGINT) AS id_post_specialist,
  CAST(REGEXP_EXTRACT(GET_JSON_OBJECT(moa.updated_message, '$.pessoas09.value'), '(\\w+)') AS BIGINT) AS id_credit_specialist,
  CAST(REGEXP_EXTRACT(GET_JSON_OBJECT(moa.updated_message, '$.pessoas4.value'), '(\\w+)') AS BIGINT) AS id_start_financing_specialist,
  CAST(REGEXP_EXTRACT(GET_JSON_OBJECT(moa.updated_message, '$.people.value'), '(\\w+)') AS BIGINT) AS id_follow_up_financing_specialist,
  CAST(REGEXP_EXTRACT(GET_JSON_OBJECT(moa.updated_message, '$.people7.value'), '(\\w+)') AS BIGINT) AS id_end_financing_specialist,
  CAST(REGEXP_EXTRACT(GET_JSON_OBJECT(moa.updated_message, '$.pessoas34.value'), '(\\w+)') AS BIGINT) AS id_notes_registry_specialist,
  CAST(REGEXP_EXTRACT(GET_JSON_OBJECT(moa.updated_message, '$.pessoas5.value'), '(\\w+)') AS BIGINT) AS id_real_estate_register_specialist,
  CAST(REGEXP_EXTRACT(GET_JSON_OBJECT(moa.updated_message, '$.lista_suspensa.value'), '(\\w+)') AS BIGINT) AS real_estate_register_office_number,
  CAST(REGEXP_EXTRACT(GET_JSON_OBJECT(moa.updated_message, '$.forma_de_pagamento4.value'), '(\\w+)') AS BIGINT) AS payment_method,
  REGEXP_EXTRACT(GET_JSON_OBJECT(moa.updated_message, '$.status07.value'), '(\\w+)')) AS payment_model,
  GET_JSON_OBJECT(moa.updated_message, '$.status06.value') AS credit_model,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.numbers.value') AS FLOAT) AS offer_acceptance_probability,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.valor_do_an_ncio.value') AS FLOAT) AS listing_sale_price,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.valor_da_proposta.value') AS FLOAT) AS price_offered_by_buyer,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.valor_do_an_ncio2.value') AS FLOAT) AS price_offered_by_seller,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.n_meros3.value') AS FLOAT) AS sale_price_agreed,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.n_umero5.value') AS FLOAT) AS brokerage_fee,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.entrada____7.value') AS FLOAT) AS deed_value,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.n_meros9.value') AS FLOAT) AS fgts_value,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.entrada____2.value') AS FLOAT) AS financing_value,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.fgts____.value') AS FLOAT) AS payment_entry_amount,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.entrada.value') AS FLOAT) AS value_in_cash,
  GET_JSON_OBJECT(moa.updated_message, '$.texto41.value') AS financing_bank,
  GET_JSON_OBJECT(moa.updated_message, '$.group.title') AS status,
  GET_JSON_OBJECT(moa.updated_message, '$.status98.value') AS negotiation_model,
  GET_JSON_OBJECT(moa.updated_message, '$.status_de_negocia__o.value') AS offer_status,
  GET_JSON_OBJECT(moa.updated_message, '$.status88.value') AS bank_analysis_status,
  GET_JSON_OBJECT(moa.updated_message, '$.an_lise_de_cr_dito.value') AS credit_status,
  GET_JSON_OBJECT(moa.updated_message, '$.status9.value') AS notary_office_status,
  GET_JSON_OBJECT(moa.updated_message, '$.cart_rio_de_notas.value') AS real_estate_register_office_status,
  GET_JSON_OBJECT(moa.updated_message, '$.status4.value') AS house_dilligence_status,
  GET_JSON_OBJECT(moa.updated_message, '$.status15.value') AS report_dilligence_status,
  GET_JSON_OBJECT(moa.updated_message, '$.status6.value') AS seller_dilligence_status,
  GET_JSON_OBJECT(moa.updated_message, '$.dropdown1.value') AS diligence_appointment_reason,
  GET_JSON_OBJECT(moa.updated_message, '$.status.value') AS sale_agreement_status,
  GET_JSON_OBJECT(moa.updated_message, '$.ccv.value') AS payment_status,
  GET_JSON_OBJECT(moa.updated_message, '$.status2.value') AS seller_payment_status,
  GET_JSON_OBJECT(moa.updated_message, '$.status_do_processo.value') AS closing_status,
  GET_JSON_OBJECT(moa.updated_message, '$.disparo_nps.value') AS sale_agreement_cancellation_reason,
  GET_JSON_OBJECT(moa.updated_message, '$.motivo_de_descarte2.value') AS drop_reason_before_acceptance,
  GET_JSON_OBJECT(moa.updated_message, '$.motivo_de_descarte_pr_.value') AS drop_reason_after_acceptance,
  CAST(REGEXP_EXTRACT(GET_JSON_OBJECT(moa.updated_message, '$.motivos_de_descarte__dm_.value'), '(\\w+)') AS BIGINT) AS current_drop_reason,
  GET_JSON_OBJECT(moa.updated_message, '$.status47.value') AS house_occupant,
  GET_JSON_OBJECT(moa.updated_message, '$.status_12.value') AS land_tenure,
  GET_JSON_OBJECT(moa.updated_message, '$.text07.value') AS tags_from_salesflow,
  COALESCE(CAST(GET_JSON_OBJECT(moa.updated_message, '$.iq_morando_.value') AS BOOLEAN), FALSE) AS has_seller_debt_payments,
  GET_JSON_OBJECT(moa.updated_message, '$.status80.value') AS has_operation_support,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.id_im_vel6.value') AS DATE) AS dt_submitted,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.data3.value') AS DATE) AS dt_deal_qualified,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.data_proposta.value') AS DATE) AS dt_accepted,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.data21.value') AS DATE) AS dt_offer_dismissed,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.data22.value') AS DATE) AS dt_last_follow_up,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.data41.value') AS DATE) AS dt_last_buyer_follow_up,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.data5.value') AS DATE) AS dt_last_seller_follow_up,
  --
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.data_assinatura_ccv4.value') AS DATE) AS dt_sale_agreement_created,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.data27.value') AS DATE) AS dt_sale_agreement_signed,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.date4.value') AS DATE) AS dt_onboarding_ended,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.data0.value') AS DATE) AS dt_bank_legal_analysis_started,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.data15.value') AS DATE) AS dt_financing_started,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.data10.value') AS DATE) AS dt_financing_ended,
  --
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.data_envio.value') AS DATE) AS dt_legaut_analysis_started,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.data218.value') AS DATE) AS dt_legaut_analysis_ended,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.data210.value') AS DATE) AS dt_legal_risk_started,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.data217.value') AS DATE) AS dt_legal_risk_ended,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.data_in_cio_dilig_ncia.value') AS DATE) AS dt_legal_analysis_ended,
  --
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.data_retorno_dilig_ncia_para_cliente5.value') AS DATE) AS dt_credit_analysis_started,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$._cr_dito__in_cio.value') AS DATE) AS dt_credit_analysis_ended,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.data_in_cio_cr_dito.value') AS DATE) AS dt_credit_analysis_result_answered,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.data24.value') AS DATE) AS dt_notes_registry_started,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.data95.value') AS DATE) AS dt_notes_registry_ended,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.data_1.value') AS DATE) AS dt_house_registry_started,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.data91.value') AS DATE) AS dt_house_registry_ended,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.data09.value') AS DATE) AS dt_sale_transacton_paid,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.data29.value') AS DATE) AS dt_sale_key_delivered,
  CAST(GET_JSON_OBJECT(moa.updated_message, '$.data26.value') AS DATE) AS dt_kit_delivered,
  moa.ts_updated
FROM
  datalake_firestore_clean.monday AS moa
INNER JOIN
  last_update AS lup
    ON moa.id = lup.id
    AND moa.ts_updated = lup.ts_last_updated
)
SELECT
  moa.id AS id_offer,
  moa.id_buyer,
  moa.id_house,
  moa.id_closing_specialist,
  moa.id_consultant,
  moa.id_agent,
  moa.id_fifty_agent,
  moa.id_pre_specialist,
  moa.id_post_specialist,
  moa.id_credit_specialist,
  moa.id_start_financing_specialist,
  moa.id_follow_up_financing_specialist,
  moa.id_end_financing_specialist,
  moa.id_notes_registry_specialist,
  moa.id_real_estate_register_specialist,
  moa.id_legal_risk_analyst,
  moa.real_estate_register_office_number,
  moa.payment_method,
  moa.payment_model,
  moa.credit_model,
  moa.offer_acceptance_probability,
  moa.listing_sale_price,
  moa.price_offered_by_buyer,
  moa.price_offered_by_seller,
  moa.sale_price_agreed,
  moa.brokerage_fee,
  moa.deed_value,
  moa.fgts_value,
  moa.financing_value,
  moa.payment_entry_amount,
  moa.value_in_cash,
  moa.financing_bank,
  moa.status,
  moa.negotiation_model,
  moa.offer_status,
  moa.bank_analysis_status,
  moa.credit_status,
  moa.notary_office_status,
  moa.real_estate_register_office_status,
  moa.house_dilligence_status,
  moa.seller_dilligence_status,
  moa.report_dilligence_status,
  moa.diligence_appointment_reason,
  moa.sale_agreement_status,
  moa.payment_status,
  moa.seller_payment_status,
  moa.closing_status,
  moa.sale_agreement_cancellation_reason,
  moa.drop_reason_before_acceptance,
  moa.drop_reason_after_acceptance,
  moa.current_drop_reason,
  -- There are 2 deprecated columns of offer drop reason in monday, but it still bring them to assemble the historic
  COALESCE(moa.current_drop_reason, moa.drop_reason_after_acceptance, moa.drop_reason_before_acceptance) AS drop_reason,
  CASE
    WHEN LOWER(COALESCE(moa.current_drop_reason, moa.drop_reason_after_acceptance, moa.drop_reason_before_acceptance)) LIKE '%buyer%' THEN 'Buyer'
    WHEN LOWER(COALESCE(moa.current_drop_reason, moa.drop_reason_after_acceptance, moa.drop_reason_before_acceptance)) LIKE '%seller%' THEN 'Seller'
    ELSE 'Other'
  END AS drop_reason_responsible,
  moa.house_occupant,
  moa.land_tenure,
  moa.tags_from_salesflow,
  CASE
    WHEN moa.payment_method = 2 THEN 'Á vista'
    WHEN moa.payment_method = 3 THEN 'Á vista + FGTS'
    WHEN moa.payment_method = 1 THEN 'Financiado'
    WHEN moa.payment_method = 4 THEN 'Financiado + FGTS'
    WHEN (moa.payment_method = 6) OR
      (moa.payment_method IS NULL) THEN 'Não definida'
    WHEN moa.payment_method = 7 THEN 'Financiado por fora'
  END AS form_of_payment,
  CASE
    WHEN moa.has_operation_support = 'SIM' THEN TRUE
    ELSE FALSE
  END AS has_operation_support,
  moa.has_seller_debt_payments,
  CASE
    WHEN moa.dt_sale_agreement_signed IS NOT NULL THEN
        CASE
          WHEN moa.status = 'CCV - Cancelado' THEN TRUE
          ELSE FALSE
        END
    ELSE NULL
  END AS is_ccv_canceled,
  CASE WHEN moa.dt_accepted <= moa.dt_offer_dismissed THEN DATEDIFF(moa.dt_offer_dismissed, moa.dt_accepted) END AS days_offer_accepted_to_offer_dismissed,
  DATEDIFF(moa.dt_sale_agreement_created, moa.dt_accepted) AS days_offer_accepted_to_sale_agreement_created,
  DATEDIFF(moa.dt_sale_agreement_signed, moa.dt_accepted) AS days_offer_accepted_to_sale_agreement_signed,
  DATEDIFF(moa.dt_sale_agreement_signed, moa.dt_sale_agreement_created) AS days_sale_agreement_created_to_sale_agreement_signed,
  moa.dt_submitted,
  moa.dt_deal_qualified,
  moa.dt_accepted,
  moa.dt_offer_dismissed,
  moa.dt_last_follow_up,
  moa.dt_last_buyer_follow_up,
  moa.dt_last_seller_follow_up,
  moa.dt_sale_agreement_created,
  moa.dt_sale_agreement_signed,
  CASE WHEN moa.status = 'CCV - Cancelado' THEN moa.dt_offer_dismissed END AS dt_sale_agreement_cancelled,
  moa.dt_onboarding_ended,
  moa.dt_bank_legal_analysis_started,
  moa.dt_financing_started,
  moa.dt_financing_ended,
  moa.dt_legaut_analysis_started,
  moa.dt_legaut_analysis_ended,
  moa.dt_legal_risk_started,
  moa.dt_legal_risk_ended,
  moa.dt_legal_analysis_ended,
  moa.dt_credit_analysis_started,
  moa.dt_credit_analysis_ended,
  moa.dt_credit_analysis_result_answered,
  moa.dt_notes_registry_started,
  moa.dt_notes_registry_ended,
  moa.dt_house_registry_started,
  moa.dt_house_registry_ended,
  moa.dt_sale_transacton_paid,
  moa.dt_sale_key_delivered,
  moa.dt_kit_delivered,
  moa.ts_updated,
  NOW() AS ts_load
FROM
  monday AS moa