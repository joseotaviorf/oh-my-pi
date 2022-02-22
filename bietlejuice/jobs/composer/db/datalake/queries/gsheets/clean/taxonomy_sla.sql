SELECT
    jornada AS journey_step,
    time AS team,
    de_para_team_looker AS de_para_team,
    codigo_assunto AS contact_theme_tag,
    codigo_detalhe_do_assunto AS contact_theme_detail_tag,
    CAST(sla_visao_operacao_em_dias_uteis AS FLOAT) AS sla_in_days,
    TO_DATE(data_inicio, 'dd/MM/yyyy') AS dt_start,
    TO_DATE(data_fim, 'dd/MM/yyyy') AS dt_end,
    TO_DATE(invalidado,'dd/MM/yyyy') AS dt_target_invalidated
FROM
    datalake_gsheets_raw.taxonomy_sla