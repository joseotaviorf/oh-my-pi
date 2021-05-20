SELECT
    aux_canal AS department,
    diretoria AS board,
    area_aux AS team,
    canal AS channel,
    area_concentrix AS concentrix_area,
    area_cc AS concentrix_area_name,
    caixa_ativa_atualmente AS active_department,
    etapa_da_jornada AS journey_step,
    frontback AS front_or_back
FROM
    datalake_gsheets_raw.department_control