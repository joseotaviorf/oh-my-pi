SELECT
    a.id_agreement AS id_negotiation,
    c.id_client AS id_customer,
    c.id_contract_external AS id_contract,
    a.id_user AS id_operator,
    ag.agency_name AS advisory,
    cp.offer_number AS id_campaign,
    a.contract_group AS creditor,
    a.agreement_type AS agreement_type,
    CASE
        WHEN u.user_type = "Externo" THEN "Assessoria"
        WHEN id_campaign IS NOT NULL THEN "Carta Campanha"
    END AS origin_agreement,
    CASE
        WHEN a.status = "Autorizado" THEN "offset"
        WHEN a.status = "Finalizado" THEN "finished"
        WHEN a.status = "Cancelado" THEN "canceled"
        ELSE a.status
    END AS negotiation_status,
    a.number_of_installments,
    a.broken_payments AS breached_installments,
    a.total_negotiated_amount_without_fees
    AS original_debt_amount,
    a.fees_amount AS fine_fee_amount,
    a.percentage_paid_agreement,
    a.additional_interest_rate,
    a.interest_rate * a.total_negotiated_amount_without_fees AS  interest_fee_amount,
    a.additional_interest_rate * a.total_negotiated_amount_without_fees AS credit_card_fee_amount,
    a.total_negotiated_amount_with_fees AS total_debt_amount,
    ad.amount_without_discount - ad.amount_with_discount AS total_discount_amount,
    ad.amount_with_discount AS negotiated_amount,
    a.ts_agreement_creation AS dt_promisse
FROM datalake_cyber_clean.agreements AS a
LEFT JOIN datalake_cyber_clean.contracts AS c
  ON a.id_contract = c.id_contract
LEFT JOIN datalake_cyber_clean.agreement_discounts AS ad
  ON a.id_agreement = ad.id_agreement
LEFT JOIN datalake_cyber_clean.campaign As cp
  ON a.id_agreement = cp.id_negotiation
LEFT JOIN datalake_cyber_clean.users AS u
  ON a.id_user = u.id_user
LEFT JOIN datalake_cyber_clean.agency AS ag
  ON u.id_agency = ag.id_agency
