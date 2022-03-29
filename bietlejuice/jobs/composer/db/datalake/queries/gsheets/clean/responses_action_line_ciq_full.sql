SELECT
    id_ciq AS id_ciq,
    CAST(id_ciq_com_imoveis_elegiveis AS BIGINT) AS id_ciq_elegibles_houses,
    CAST(id_imovel_ AS BIGINT) AS id_house,
    analista_responsavel AS responsible_analyst,
    frente AS front,
    prioridade_indicada AS indicated_priority,
    pitch_passado AS previous_pitch,
    resultado_da_ligacao_ AS call_results,
    ciq_receptivo AS receptive_ciq,
    identificou_algum_problema AS identify_problem,
    comentario AS comment,
    enviou_macro_qual AS macro_sent,
    melhor_periodo_para_contato AS best_time_to_contact,
    qual_frequencia_voce_deseja_receber_nosso_contato AS frequency_to_recieve_our_contact,
    gostaria_de_ser_atendido_por_um_analista_especifico AS receive_attendiment_specific_analyst,
    TO_TIMESTAMP(timestamp, 'M/d/yyyy H:mm:SS') AS ts_created
FROM
    datalake_gsheets_raw.tratativas_actionline_ciq_full_responses