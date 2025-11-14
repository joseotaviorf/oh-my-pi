SELECT
    NULLIF(`ID offer`, '') AS id_offer,
    NULLIF(`ID house`, '') AS id_house,
    CASE
        WHEN LOWER(NULLIF(`Offer cancelada`, '')) = 'sim' THEN TRUE
        WHEN LOWER(NULLIF(`Offer cancelada`, '')) = 'não' THEN FALSE
        ELSE NULL
    END AS is_offer_canceled,
    CASE
        WHEN LOWER(NULLIF(`Distrato c/ corretagem`, '')) = 'sim' THEN TRUE
        WHEN LOWER(NULLIF(`Distrato c/ corretagem`, '')) = 'não' THEN FALSE
        ELSE NULL
    END AS is_cancellation_with_brokerage,
    CASE
        WHEN LOWER(NULLIF(`É 3p leads?`, '')) = 'sim' THEN TRUE
        WHEN LOWER(NULLIF(`É 3p leads?`, '')) = 'não' THEN FALSE
        ELSE NULL
    END AS is_3p_leads,
    CASE
        WHEN LOWER(NULLIF(`É mercado primário?`, '')) = 'sim' THEN TRUE
        WHEN LOWER(NULLIF(`É mercado primário?`, '')) = 'não' THEN FALSE
        ELSE NULL
    END AS is_primary_market,
    CASE
        WHEN LOWER(NULLIF(`É minha casa minha vida?`, '')) = 'sim' THEN TRUE
        WHEN LOWER(NULLIF(`É minha casa minha vida?`, '')) = 'não' THEN FALSE
        ELSE NULL
    END AS is_my_house_my_life,
    CASE
        WHEN LOWER(NULLIF(`É perda reconhecida?`, '')) = 'sim' THEN TRUE
        WHEN LOWER(NULLIF(`É perda reconhecida?`, '')) = 'não' THEN FALSE
        ELSE NULL
    END AS is_recognized_loss,
    CASE
        WHEN LOWER(NULLIF(`Recomenda WO`, '')) = 'sim' THEN TRUE
        WHEN LOWER(NULLIF(`Recomenda WO`, '')) = 'não' THEN FALSE
        ELSE NULL
    END AS recommends_wo,
    CASE
        WHEN LOWER(NULLIF(Quitado, '')) = 'sim' THEN TRUE
        WHEN LOWER(NULLIF(Quitado, '')) = 'não' THEN FALSE
        ELSE NULL
    END AS is_settled,
    CASE
        WHEN LOWER(NULLIF(`Notificação Extrajudicial`, '')) = 'sim' THEN TRUE
        WHEN LOWER(NULLIF(`Notificação Extrajudicial`, '')) = 'não' THEN FALSE
        ELSE NULL
    END AS has_extrajudicial_notification,
    NULLIF(`Status da offer2`, '') AS offer_status,
    NULLIF(`Status cobrança `, '') AS collection_status,
    CAST(NULLIF(`Tempo na base`, '') AS INT) AS time_in_base,
    CAST(NULLIF(`Tempo desde a última interação`, '') AS INT) AS time_since_last_interaction,
    NULLIF(`Aging desde a última interação`, '') AS aging_since_last_interaction,
    NULLIF(`Possível WO`, '') AS possible_wo,
    NULLIF(Status, '') AS status,
    NULLIF(`Status da offer11`, '') AS offer_status_2,
    NULLIF(`Tipo pagamento`, '') AS payment_type,
    NULLIF(Produto, '') AS product,
    NULLIF(`Partner - Rede`, '') AS partner_network,
    NULLIF(`Tag Vendas`, '') AS sales_tag,
    NULLIF(Vendedor, '') AS seller,
    NULLIF(Telefone, '') AS phone,
    NULLIF(`E-mail`, '') AS email,
    NULLIF(`Endereço`, '') AS address,
    NULLIF(Analista, '') AS analyst,
    NULLIF(`Status detalhado`, '') AS detailed_status,
    NULLIF(`Status da cobrança`, '') AS collection_status_2,
    NULLIF(`Motivo da cobrança`, '') AS collection_reason,
    NULLIF(`Ligação`, '') AS call_record,
    NULLIF(`TIcket Zendesk`, '') AS zendesk_ticket,
    NULLIF(Condicionante, '') AS condition,
    NULLIF(`Demais contatos`, '') AS other_contacts,
    CAST(NULLIF(`Valor de corretagem`, '') AS DOUBLE) AS brokerage_amount,
    CAST(NULLIF(`Saldo recebido `, '') AS DOUBLE) AS balance_received,
    CAST(NULLIF(`Saldo a receber `, '') AS DOUBLE) AS balance_to_receive,
    CAST(NULLIF(`Nº de tentativas de contato`, '') AS INT) AS contact_attempts_count,
    TO_DATE(NULLIF(`Data de entrada em histórico`, ''), 'd/M/y') AS dt_entry_history,
    TO_DATE(NULLIF(`Data de entrada em rotina`, ''), 'd/M/y') AS dt_entry_routine,
    TO_DATE(NULLIF(`Data CCV assinado`, ''), 'd/M/y') AS dt_ccv_signed,
    TO_DATE(NULLIF(`Data CRI`, ''), 'd/M/y') AS dt_cri,
    TO_DATE(NULLIF(`Data diligência`, ''), 'd/M/y') AS dt_diligence,
    TO_DATE(NULLIF(`Data do cancelamento`, ''), 'd/M/y') AS dt_cancellation,
    TO_DATE(NULLIF(`Data resgate da offer`, ''), 'd/M/y') AS dt_offer_rescue,
    TO_DATE(NULLIF(`Data financiamento`, ''), 'd/M/y') AS dt_financing,
    TO_DATE(NULLIF(`Data início cobrança`, ''), 'd/M/y') AS dt_collection_start,
    TO_DATE(NULLIF(`Data da quitação`, ''), 'd/M/y') AS dt_settlement,
    TO_DATE(NULLIF(`Data Notificação EJ`, ''), 'd/M/y') AS dt_extrajudicial_notification,
    TO_DATE(NULLIF(`Data Condicionante`, ''), 'd/M/y') AS dt_condition,
    TO_DATE(NULLIF(`Data primeiro contato`, ''), 'd/M/y') AS dt_first_contact,
    NOW() AS ts_load
FROM
    datalake_gsheets_raw.collections_for_sale_journey_history
