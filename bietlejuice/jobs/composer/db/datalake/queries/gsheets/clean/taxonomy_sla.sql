SELECT
    jornada AS journey_step,
    time AS team,
    de_para_team_looker AS de_para_team,
    codigo_assunto AS contact_theme_tag,
    codigo_detalhe_do_assunto AS contact_theme_detail_tag,
    CAST(sla_visao_operacao_em_dias_uteis AS FLOAT) AS sla_in_days
FROM
    datalake_gsheets_raw.taxonomy_sla