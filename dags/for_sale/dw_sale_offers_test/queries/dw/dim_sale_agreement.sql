SELECT
    eso.id_offer AS sk_offer,
    eso.ccv_type,
    eso.sale_agreement_status,
    eso.offer_flow,
    eso.business_unit,
    eso.sale_agreement_cancellation_reason,
    eso.sale_price_agreed,
    eso.brokerage_fee,
    eso.current_payment_method AS payment_method,
    eso.credit_model,
    CASE
        WHEN eso.is_ccv_5a_model IS NULL THEN "Not Answered"
        WHEN eso.is_ccv_5a_model IS FALSE THEN "Not a 5A model"
        WHEN eso.is_ccv_5a_model IS TRUE THEN "Is a 5A model"
        ELSE "Undefined"
    END AS ccv_model,
    eso.closing_status,
    eso.house_dilligence_status,
    eso.seller_dilligence_status,
    eso.report_dilligence_status,
    eso.diligence_appointment_reason,
    eso.has_used_fgts_in_payment,
    eso.has_seller_debt_payments,
    eso.is_ccv_canceled,
    eso.is_3p_supply,
    eso.is_3p_demand,
    eso.is_a_rescued_ccv,
    CAST(eso.ts_sale_agreement_signed AS TIMESTAMP) AS ts_sale_agreement_signed,
    CAST(eso.ts_sale_agreement_canceled AS TIMESTAMP) AS ts_sale_agreement_cancelled,
    NOW() AS ts_load
FROM
    datalake_sale_offer.sale_offers eso
WHERE
    eso.ts_sale_agreement_signed IS NOT NULL