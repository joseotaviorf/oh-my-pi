SELECT
    analista AS agent_name,
    email,
    empresa AS agent_company,
    atividade AS activity,
    ranking,
    TO_DATE(data_de_inicio_na_area, 'dd/MM/yyyy') AS dt_start,
    TO_DATE(data_de_final_na_area, 'dd/MM/yyyy') AS dt_end
FROM
    datalake_gsheets_raw.agents_ranking_offboarding