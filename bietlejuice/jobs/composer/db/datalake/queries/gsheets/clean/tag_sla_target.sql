SELECT
    jornada AS journey,
    tag,
    CAST(sla AS FLOAT) AS sla,
    DATE(data_inicio) AS dt_start,
    DATE(data_fim) AS dt_end
FROM
    datalake_gsheets_raw.tag_sla_target