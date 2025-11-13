SELECT
    NULLIF(ID_offer, '') AS id_offer,
    NULLIF(ID_house, '') AS id_house,
    CASE
        WHEN LOWER(NULLIF(Offer_cancelada, '')) = 'sim' THEN TRUE
        WHEN LOWER(NULLIF(Offer_cancelada, '')) = 'não' THEN FALSE
        ELSE NULL
    END AS is_offer_canceled,
    CASE
        WHEN LOWER(NULLIF(Distrato_c_corretagem, '')) = 'sim' THEN TRUE
        WHEN LOWER(NULLIF(Distrato_c_corretagem, '')) = 'não' THEN FALSE
        ELSE NULL
    END AS is_cancellation_with_brokerage,
    CASE
        WHEN LOWER(NULLIF(É_3p_leads_, '')) = 'sim' THEN TRUE
        WHEN LOWER(NULLIF(É_3p_leads_, '')) = 'não' THEN FALSE
        ELSE NULL
    END AS is_3p_leads,
    CASE
        WHEN LOWER(NULLIF(É_mercado_primário_, '')) = 'sim' THEN TRUE
        WHEN LOWER(NULLIF(É_mercado_primário_, '')) = 'não' THEN FALSE
        ELSE NULL
    END AS is_primary_market,
    CASE
        WHEN LOWER(NULLIF(É_minha_casa_minha_vida_, '')) = 'sim' THEN TRUE
        WHEN LOWER(NULLIF(É_minha_casa_minha_vida_, '')) = 'não' THEN FALSE
        ELSE NULL
    END AS is_my_house_my_life,
    CASE
        WHEN LOWER(NULLIF(É_perda_reconhecida_, '')) = 'sim' THEN TRUE
        WHEN LOWER(NULLIF(É_perda_reconhecida_, '')) = 'não' THEN FALSE
        ELSE NULL
    END AS is_recognized_loss,
    CASE
        WHEN LOWER(NULLIF(Recomenda_WO, '')) = 'sim' THEN TRUE
        WHEN LOWER(NULLIF(Recomenda_WO, '')) = 'não' THEN FALSE
        ELSE NULL
    END AS recommends_wo,
    CASE
        WHEN LOWER(NULLIF(Quitado, '')) = 'sim' THEN TRUE
        WHEN LOWER(NULLIF(Quitado, '')) = 'não' THEN FALSE
        ELSE NULL
    END AS is_settled,
    CASE
        WHEN LOWER(NULLIF(Notificação_Extrajudicial, '')) = 'sim' THEN TRUE
        WHEN LOWER(NULLIF(Notificação_Extrajudicial, '')) = 'não' THEN FALSE
        ELSE NULL
    END AS has_extrajudicial_notification,
    NULLIF(Status_da_offer, '') AS offer_status,
    NULLIF(Status_cobrança, '') AS collection_status,
    NULLIF(Tempo_na_base, '') AS time_in_base,
    NULLIF(Tempo_desde_a_última_interação, '') AS time_since_last_interaction,
    NULLIF(Aging_desde_a_última_interação, '') AS aging_since_last_interaction,
    NULLIF(Possível_WO, '') AS possible_wo,
    NULLIF(Status, '') AS status,
    NULLIF(Status_da_offer_2, '') AS offer_status_2,
    NULLIF(Tipo_pagamento, '') AS payment_type,
    NULLIF(Produto, '') AS product,
    NULLIF(Partner___Rede, '') AS partner_network,
    NULLIF(Tag_Vendas, '') AS sales_tag,
    NULLIF(Vendedor, '') AS seller,
    NULLIF(Telefone, '') AS phone,
    NULLIF(E_mail, '') AS email,
    NULLIF(Endereço, '') AS address,
    NULLIF(Analista, '') AS analyst,
    NULLIF(Status_detalhado, '') AS detailed_status,
    NULLIF(Status_da_cobrança_2, '') AS collection_status_2,
    NULLIF(Motivo_da_cobrança, '') AS collection_reason,
    NULLIF(Ligação, '') AS call_record,
    NULLIF(TIcket_Zendesk, '') AS zendesk_ticket,
    NULLIF(Condicionante, '') AS condition,
    NULLIF(Demais_contatos, '') AS other_contacts,
    CAST(NULLIF(Valor_de_corretagem, '') AS DOUBLE) AS brokerage_amount,
    CAST(NULLIF(Saldo_recebido, '') AS DOUBLE) AS balance_received,
    CAST(NULLIF(Saldo_a_receber, '') AS DOUBLE) AS balance_to_receive,
    CAST(NULLIF(Nº_de_tentativas_de_contato, '') AS INT) AS contact_attempts_count,
    DATE(NULLIF(Data_de_entrada_em_histórico, ''), 'd/M/y') AS dt_entry_history,
    DATE(NULLIF(Data_de_entrada_em_rotina, ''), 'd/M/y') AS dt_entry_routine,
    DATE(NULLIF(Data_CCV_assinado, ''), 'd/M/y') AS dt_ccv_signed,
    DATE(NULLIF(Data_CRI, ''), 'd/M/y') AS dt_cri,
    DATE(NULLIF(Data_diligência, ''), 'd/M/y') AS dt_diligence,
    DATE(NULLIF(Data_do_cancelamento, ''), 'd/M/y') AS dt_cancellation,
    DATE(NULLIF(Data_resgate_da_offer, ''), 'd/M/y') AS dt_offer_rescue,
    DATE(NULLIF(Data_financiamento, ''), 'd/M/y') AS dt_financing,
    DATE(NULLIF(Data_início_cobrança, ''), 'd/M/y') AS dt_collection_start,
    DATE(NULLIF(Data_da_quitação, ''), 'd/M/y') AS dt_settlement,
    DATE(NULLIF(Data_Notificação_EJ, ''), 'd/M/y') AS dt_extrajudicial_notification,
    DATE(NULLIF(Data_Condicionante, ''), 'd/M/y') AS dt_condition,
    DATE(NULLIF(Data_primeiro_contato, ''), 'd/M/y') AS dt_first_contact,
    NOW AS ts_load
FROM
    datalake_gsheets_raw.collections_for_sale_journey_history
