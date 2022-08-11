SELECT
    jornada AS journey,
    tag,
    CAST(sla AS FLOAT) AS sla,
    TO_DATE(data_inicio, 'dd/MM/yyyy') AS dt_start,
    TO_DATE(data_fim, 'dd/MM/yyyy') AS dt_end
FROM
    datalake_gsheets_raw.tag_sla_target
