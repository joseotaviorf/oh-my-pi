SELECT
    NULLIF(id_offer, '') AS id_offer,
    CAST(NULLIF(id_house, '') AS INT) AS id_house,
    CASE
        WHEN LOWER(NULLIF(offer_cancelada, '')) = 'sim' THEN TRUE
        WHEN LOWER(NULLIF(offer_cancelada, '')) = 'não' THEN FALSE
        ELSE NULL
    END AS is_offer_canceled,
    CASE
        WHEN LOWER(NULLIF(distrato_c_corretagem, '')) = 'sim' THEN TRUE
        WHEN LOWER(NULLIF(distrato_c_corretagem, '')) = 'não' THEN FALSE
        ELSE NULL
    END AS is_cancellation_with_brokerage,
    CASE
        WHEN LOWER(NULLIF(e_3p_leads, '')) = 'sim' THEN TRUE
        WHEN LOWER(NULLIF(e_3p_leads, '')) = 'não' THEN FALSE
        ELSE NULL
    END AS is_3p_leads,
    CASE
        WHEN LOWER(NULLIF(e_mercado_primario, '')) = 'sim' THEN TRUE
        WHEN LOWER(NULLIF(e_mercado_primario, '')) = 'não' THEN FALSE
        ELSE NULL
    END AS is_primary_market,
    CASE
        WHEN LOWER(NULLIF(e_minha_casa_minha_vida, '')) = 'sim' THEN TRUE
        WHEN LOWER(NULLIF(e_minha_casa_minha_vida, '')) = 'não' THEN FALSE
        ELSE NULL
    END AS is_my_house_my_life,
    CASE
        WHEN LOWER(NULLIF(e_perda_reconhecida, '')) = 'sim' THEN TRUE
        WHEN LOWER(NULLIF(e_perda_reconhecida, '')) = 'não' THEN FALSE
        ELSE NULL
    END AS is_recognized_loss,
    CASE
        WHEN LOWER(NULLIF(recomenda_wo, '')) = 'sim' THEN TRUE
        WHEN LOWER(NULLIF(recomenda_wo, '')) = 'não' THEN FALSE
        ELSE NULL
    END AS recommends_wo,
    CASE
        WHEN LOWER(NULLIF(quitado, '')) = 'sim' THEN TRUE
        WHEN LOWER(NULLIF(quitado, '')) = 'não' THEN FALSE
        ELSE NULL
    END AS is_settled,
    CASE
        WHEN LOWER(NULLIF(notificacao_extrajudicial, '')) = 'sim' THEN TRUE
        WHEN LOWER(NULLIF(notificacao_extrajudicial, '')) = 'não' THEN FALSE
        ELSE NULL
    END AS has_extrajudicial_notification,
    CASE
        WHEN LOWER(NULLIF(retorno_idactum, '')) = 'sim' THEN TRUE
        ELSE NULL
    END AS has_idactum_return,
    NULLIF(modelo_da_offer, '') AS offer_model,
    NULLIF(status_cobranca, '') AS collection_status,
    CAST(NULLIF(tempo_na_base, '') AS INT) AS time_in_base,
    CAST(NULLIF(tempo_desde_a_ultima_interacao, '') AS INT) AS time_since_last_interaction,
    NULLIF(aging_desde_a_ultima_interacao, '') AS aging_since_last_interaction,
    NULLIF(possivel_wo_h12025, '') AS possible_wo_h1_2025,
    NULLIF(status, '') AS status,
    NULLIF(status_da_offer, '') AS offer_status,
    NULLIF(tipo_pagamento, '') AS payment_type,
    NULLIF(produto, '') AS product,
    NULLIF(partner_rede, '') AS partner_network,
    NULLIF(tag_vendas, '') AS sales_tag,
    NULLIF(vendedor, '') AS seller,
    NULLIF(telefone, '') AS phone,
    NULLIF(email, '') AS email,
    NULLIF(endereco, '') AS address,
    NULLIF(analista, '') AS analyst,
    NULLIF(status_detalhado, '') AS detailed_status,
    NULLIF(status_da_cobranca, '') AS collection_status_2,
    NULLIF(motivo_da_cobranca, '') AS collection_reason,
    NULLIF(ligacao, '') AS call_record,
    NULLIF(ticket_zendesk, '') AS zendesk_ticket,
    NULLIF(condicionante, '') AS condition,
    NULLIF(demais_contatos, '') AS other_contacts,
    CAST(NULLIF(REPLACE(REGEXP_REPLACE(NULLIF(valor_de_corretagem, ''), '[^0-9,-]', ''), ',', '.'), '') AS DOUBLE) AS brokerage_amount,
    CAST(NULLIF(REPLACE(REGEXP_REPLACE(NULLIF(saldo_recebido, ''), '[^0-9,-]', ''), ',', '.'), '') AS DOUBLE) AS balance_received,
    CAST(NULLIF(REPLACE(REGEXP_REPLACE(NULLIF(saldo_a_receber, ''), '[^0-9,-]', ''), ',', '.'), '') AS DOUBLE) AS balance_to_receive,
    CAST(NULLIF(no_de_tentativas_de_contato, '') AS INT) AS contact_attempts_count,
    TO_DATE(NULLIF(data_entrada, ''), 'd/M/y') AS dt_entry,
    TO_DATE(NULLIF(data_ccv_assinado, ''), 'd/M/y') AS dt_ccv_signed,
    TO_DATE(NULLIF(data_cri, ''), 'd/M/y') AS dt_cri,
    TO_DATE(NULLIF(data_diligencia, ''), 'd/M/y') AS dt_diligence,
    TO_DATE(NULLIF(data_do_cancelamento, ''), 'd/M/y') AS dt_cancellation,
    TO_DATE(NULLIF(data_resgate_da_offer, ''), 'd/M/y') AS dt_offer_rescue,
    TO_DATE(NULLIF(data_financiamento, ''), 'd/M/y') AS dt_financing,
    TO_DATE(NULLIF(data_inicio_cobranca, ''), 'd/M/y') AS dt_collection_start,
    TO_DATE(NULLIF(data_da_quitacao, ''), 'd/M/y') AS dt_settlement,
    TO_DATE(NULLIF(data_notificacao_ej, ''), 'd/M/y') AS dt_extrajudicial_notification,
    TO_DATE(NULLIF(data_condicionante, ''), 'd/M/y') AS dt_condition,
    TO_DATE(NULLIF(data_primeiro_contato, ''), 'd/M/y') AS dt_first_contact,
    TO_DATE(NULLIF(data_prevista_de_contato, ''), 'd/M/y') AS dt_expected_contact,
    NOW() AS ts_load
FROM
    datalake_gsheets_raw.collections_for_sale_journey_routine
