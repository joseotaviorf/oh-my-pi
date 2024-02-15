SELECT
    email,
    nome AS first_name,
    sobrenome AS last_name,
    CASE
        WHEN acesso_liberado = "Sim" THEN true
        ELSE false
    END AS is_access_granted,
    cargo AS job_title,
    turma AS class_origin,
    ts_load
FROM
    datalake_gsheets_raw.data_analytics_training_editor_superset
