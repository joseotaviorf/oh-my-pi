WITH data_sources AS (
    SELECT   
        so.id_offer,
        so.id_buyer,
        so.id_owner,
        so.id_house,
        COALESCE('ID_VENDAS_' || sof.id_consultant, 'ID_MONDAY_' || m.id_closing_specialist) AS id_closing_specialist,
        COALESCE('ID_VENDAS_' || sof.id_legal_risk_analyst, 'ID_MONDAY_' || m.id_legal_risk_analyst) AS id_legal_risk_analyst,
        COALESCE('ID_VENDAS_' || sof.id_pre_specialist, 'ID_MONDAY_' || m.id_pre_specialist) AS id_pre_specialist,
        COALESCE('ID_VENDAS_' || sof.id_post_specialist, 'ID_MONDAY_' || m.id_post_specialist) AS id_post_specialist,
        COALESCE('ID_VENDAS_' || sof.id_start_financing_specialist, 'ID_MONDAY_' || m.id_start_financing_specialist) AS id_start_financing_specialist,
        COALESCE('ID_VENDAS_' || sof.id_follow_up_financing_specialist, 'ID_MONDAY_' || m.id_follow_up_financing_specialist) AS id_follow_up_financing_specialist,
        COALESCE('ID_VENDAS_' || sof.id_end_financing_specialist, 'ID_MONDAY_' || m.id_end_financing_specialist) AS id_end_financing_specialist,
        COALESCE('ID_VENDAS_' || sof.id_credit_specialist, 'ID_MONDAY_' || m.id_credit_specialist) AS id_credit_specialist,
        COALESCE('ID_VENDAS_' || sof.id_notes_registry_specialist, 'ID_MONDAY_' || m.id_notes_registry_specialist) AS id_notes_registry_specialist,
        COALESCE('ID_VENDAS_' || sof.id_real_estate_register_specialist, 'ID_MONDAY_' || m.id_real_estate_register_specialist) AS id_real_estate_register_specialist,
        so.dt_sale_agreement_created,
        so.dt_sale_agreement_signed,
        so.dt_sale_agreement_cancelled,
        COALESCE(sof.dt_onboarding_ended, m.dt_onboarding_ended) AS dt_onboarding_ended,
        COALESCE(sof.dt_legal_analysis_ended, m.dt_legal_analysis_ended) AS dt_legal_analysis_ended,
        COALESCE(sof.dt_legaut_analysis_started, m.dt_legaut_analysis_started) AS dt_legaut_analysis_started,
        COALESCE(sof.dt_legaut_analysis_ended, m.dt_legaut_analysis_ended) AS dt_legaut_analysis_ended,
        COALESCE(sof.dt_legal_risk_started, m.dt_legal_risk_started) AS dt_legal_risk_started,
        COALESCE(sof.dt_legal_risk_ended, m.dt_legal_risk_ended) AS dt_legal_risk_ended,
        COALESCE(sof.dt_bank_legal_analysis_started, m.dt_bank_legal_analysis_started) AS dt_bank_legal_analysis_started,
        COALESCE(sof.dt_credit_analysis_started, m.dt_credit_analysis_started) AS dt_credit_analysis_started,
        COALESCE(sof.dt_credit_analysis_ended, m.dt_credit_analysis_ended) AS dt_credit_analysis_ended,
        COALESCE(sof.dt_financing_started, m.dt_financing_started) AS dt_financing_started,
        COALESCE(sof.dt_financing_ended, m.dt_financing_ended) AS dt_financing_ended,
        COALESCE(sof.dt_notes_registry_started, m.dt_notes_registry_started) AS dt_notes_registry_started,
        COALESCE(sof.dt_notes_registry_ended, m.dt_notes_registry_ended) AS dt_notes_registry_ended,
        so.dt_house_registry_started,
        so.dt_house_registry_ended,
        COALESCE(sof.dt_sale_key_delivered, m.dt_sale_key_delivered) AS dt_sale_key_delivered,
        so.dt_sale_transacton_paid,
        CASE 
            WHEN so.current_payment_method LIKE 'FINANCED%'
                AND CONCAT(ms.dt_occurence, COALESCE(sof.dt_legal_analysis_ended, m.dt_legal_analysis_ended), COALESCE(sof.dt_credit_analysis_ended, m.dt_credit_analysis_ended)) IS NOT NULL
                    THEN DATE(GREATEST(ms.dt_occurence, COALESCE(sof.dt_legal_analysis_ended, m.dt_legal_analysis_ended), COALESCE(sof.dt_credit_analysis_ended, m.dt_credit_analysis_ended)))
            WHEN so.current_payment_method LIKE 'CASH%'
                AND CONCAT(ms.dt_occurence, COALESCE(sof.dt_legal_analysis_ended, m.dt_legal_analysis_ended)) IS NOT NULL
                    THEN DATE(GREATEST(ms.dt_occurence, COALESCE(sof.dt_legal_analysis_ended, m.dt_legal_analysis_ended)))
            ELSE NULL
        END AS dt_payment_allowed,
        ms.dt_occurence AS dt_down_payment,
        so.ts_updated
    FROM
        datalake_offer.sale_offer so
    LEFT JOIN
        datalake_firestore.monday AS m
            ON so.id_offer = m.id_offer
    LEFT JOIN
        datalake_sale_offer_flows.sale_offer_flows AS sof
            ON so.id_offer = sof.id_offer
    LEFT JOIN
        datalake_monopoly.sale AS ms
            ON ms.id_external_offer = so.id_offer
    WHERE
        so.dt_sale_agreement_signed IS NOT NULL
)
SELECT
    id_offer,
    id_buyer,
    id_owner,
    id_house,
    id_closing_specialist,
    id_legal_risk_analyst,
    id_pre_specialist,
    id_post_specialist,
    id_start_financing_specialist,
    id_follow_up_financing_specialist,
    id_end_financing_specialist,
    id_credit_specialist,
    id_notes_registry_specialist,
    id_real_estate_register_specialist,
    DATEDIFF(dt_legaut_analysis_started, dt_sale_agreement_created) AS days_sale_agreement_created_to_legaut_analysis_started,
    DATEDIFF(dt_house_registry_started, dt_sale_agreement_signed) AS days_sale_agreement_signed_to_house_registry_started,
    DATEDIFF(dt_house_registry_ended, dt_sale_agreement_signed) AS days_sale_agreement_signed_to_house_registry_ended,
    DATEDIFF(dt_sale_agreement_cancelled, dt_sale_agreement_signed) AS days_sale_agreement_signed_to_sale_agreement_cancelled,
    DATEDIFF(dt_onboarding_ended, dt_sale_agreement_signed) AS days_sale_agreement_signed_to_onboarding_ended,
    DATEDIFF(dt_credit_analysis_started, dt_sale_agreement_signed) AS days_sale_agreement_signed_to_credit_analysis_started,
    DATEDIFF(dt_credit_analysis_ended, dt_sale_agreement_signed) AS days_sale_agreement_signed_to_credit_analysis_ended,
    DATEDIFF(dt_financing_started, dt_sale_agreement_signed) AS days_sale_agreement_signed_to_financing_started,
    DATEDIFF(dt_notes_registry_started, dt_sale_agreement_signed) AS days_sale_agreement_signed_to_notes_registry_started,
    DATEDIFF(dt_notes_registry_ended, dt_sale_agreement_signed) AS days_sale_agreement_signed_to_notes_registry_ended,
    DATEDIFF(dt_legaut_analysis_started, dt_sale_agreement_signed) AS days_sale_agreement_signed_to_legaut_analysis_started,
    DATEDIFF(dt_legaut_analysis_ended, dt_sale_agreement_signed) AS days_sale_agreement_signed_to_legaut_analysis_ended,
    DATEDIFF(dt_legal_risk_ended, dt_sale_agreement_signed) AS days_sale_agreement_signed_to_legal_risk_ended,
    DATEDIFF(dt_bank_legal_analysis_started, dt_sale_agreement_signed) AS days_sale_agreement_signed_to_bank_legal_analysis_started,
    DATEDIFF(dt_legal_risk_ended, dt_legal_risk_started) AS days_legal_risk_started_to_legal_risk_ended,
    DATEDIFF(dt_legal_analysis_ended, dt_legal_risk_ended) AS days_legal_risk_ended_to_legal_analysis_ended,
    DATEDIFF(dt_legaut_analysis_ended, dt_legaut_analysis_started) AS days_legaut_analysis_started_to_legaut_analysis_ended,
    DATEDIFF(dt_legal_risk_ended, dt_legaut_analysis_ended) AS days_legaut_analysis_ended_to_legal_risk_ended,
    DATEDIFF(dt_notes_registry_ended, dt_legal_analysis_ended) AS days_legal_analysis_ended_notes_registry_ended,
    DATEDIFF(dt_bank_legal_analysis_started, dt_legal_analysis_ended) AS days_legal_analysis_ended_to_bank_legal_analysis_started,
    DATEDIFF(dt_financing_ended, dt_bank_legal_analysis_started) AS days_bank_legal_analysis_started_to_financing_ended,
    DATEDIFF(dt_house_registry_started, dt_bank_legal_analysis_started) AS days_bank_legal_analysis_started_to_house_registry_started,
    DATEDIFF(dt_credit_analysis_ended, dt_credit_analysis_started) AS days_credit_analysis_started_to_credit_analysis_ended,
    DATEDIFF(dt_bank_legal_analysis_started, dt_credit_analysis_ended) AS days_credit_analysis_ended_to_bank_legal_analysis_started,
    DATEDIFF(dt_financing_ended, dt_financing_started) AS days_financing_started_to_financing_ended,
    DATEDIFF(dt_house_registry_ended, dt_financing_ended) AS days_financing_ended_to_house_registry_ended,
    DATEDIFF(dt_house_registry_started, dt_financing_ended) AS days_financing_ended_to_house_registry_started,
    DATEDIFF(dt_notes_registry_ended, dt_notes_registry_started) AS days_notes_registry_started_to_notes_registry_ended,
    DATEDIFF(dt_house_registry_ended, dt_house_registry_started) AS days_house_registry_started_to_house_registry_ended,
    DATEDIFF(dt_house_registry_started, dt_notes_registry_ended) AS days_notes_registry_ended_to_house_registry_started,
    DATEDIFF(dt_house_registry_ended, dt_notes_registry_ended) AS days_notes_registry_ended_to_house_registry_ended,
    DATEDIFF(dt_sale_key_delivered, dt_house_registry_ended) AS days_house_registry_ended_to_sale_key_delivered,
    DATEDIFF(dt_sale_transacton_paid, dt_house_registry_ended) AS days_house_registry_ended_to_sale_transaction_paid,
    dt_sale_agreement_created,
    dt_sale_agreement_signed,
    dt_sale_agreement_cancelled,
    dt_onboarding_ended,
    dt_legal_analysis_ended,
    dt_legaut_analysis_started,
    dt_legaut_analysis_ended,
    dt_legal_risk_started,
    dt_legal_risk_ended,
    dt_bank_legal_analysis_started,
    dt_credit_analysis_started,
    dt_credit_analysis_ended,
    dt_financing_started,
    dt_financing_ended,
    dt_notes_registry_started,
    dt_notes_registry_ended,
    dt_house_registry_started,
    dt_house_registry_ended,
    dt_sale_key_delivered,
    dt_sale_transacton_paid,
    dt_payment_allowed,
    dt_down_payment,
    ts_updated,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    data_sources
