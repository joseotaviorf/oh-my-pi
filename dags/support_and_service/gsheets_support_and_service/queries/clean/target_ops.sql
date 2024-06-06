SELECT
    date_type,
    descricao AS description,
    indice_setor AS index,
    level,
    subjorney AS sub_journey,
    journey,
    team,
    channel,
    empresa AS company,
    indicador AS metric_name,
    valor AS target,
    date AS dt_target
FROM
    datalake_gsheets_raw.target_ops
