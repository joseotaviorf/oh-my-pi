SELECT
    id_house,
    asp_database AS asp_database,
    asp_listing AS asp_listing,
    endereco_de_email AS asp_assignee_email,
    asp_responsavel AS asp_assignee_name,
    INT(NULLIF(preco_do_anuncio_no_momento_do_atendimento, '')) AS sale_price_listing,
    INT(NULLIF(preco_da_calculadora, '')) AS sale_price_calculator, 
    INT(NULLIF(preco_apos_alteracao, '')) AS sale_price_after_change,
    CASE WHEN LENGTH(acaooes_asp_agendar_nova_sessao_de_fotos) > 0 THEN TRUE ELSE FALSE END AS has_action_book_new_photo_session,
    CASE WHEN LENGTH(acaooes_asp_alterar_condicao_de_entrada) > 0 THEN TRUE ELSE FALSE END AS has_action_change_house_entrance,
    CASE WHEN LENGTH(acaooes_asp_alterar_horarios_de_visita) > 0 THEN TRUE ELSE FALSE END AS has_action_change_available_visit_hours,
    CASE WHEN LENGTH(acaooes_asp_alterar_preco_do_imovel) > 0 THEN TRUE ELSE FALSE END AS has_action_change_sale_price,
    CASE WHEN LENGTH(acao__incluir_ou_corrigir_info_do_anuncio) > 0 THEN TRUE ELSE FALSE END AS has_action_change_listing_description,
    CASE WHEN LENGTH(acaooes_asp_despublicar_imovel) > 0 THEN TRUE ELSE FALSE END AS has_phase_out_unpublish_listing,
    CASE WHEN LENGTH(acaooes_asp_disponibilizar_lockbox) > 0 THEN TRUE ELSE FALSE END AS has_action_make_lockbox_available,
    CASE WHEN LENGTH(acaooes_asp_enviar_para_is_novo_imovel_para_cadastro) > 0 THEN TRUE ELSE FALSE END AS has_action_new_listing_to_be_sent_to_is_team,
    CASE WHEN LENGTH(acaooes_asp_suspender_imovel) > 0 THEN TRUE ELSE FALSE END AS has_phase_out_suspend_listing,
    CASE WHEN LENGTH(acaooes_asp_nenhuma_acao_anuncio_esta_adequado) > 0 THEN TRUE ELSE FALSE END AS has_no_necessary_action,
    DATE(NULLIF(carimbo_de_datahora,'')) AS dt_form_entry
FROM
    datalake_gsheets_raw.sale_asp_form_responses_2022q1