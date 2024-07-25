SELECT
    codigo AS id_project,
    nome AS project_name,
    CASE
        WHEN inativo = 'S' THEN TRUE
        WHEN inativo = 'N' THEN FALSE
        ELSE NULL
    END AS is_inactive
FROM
    datalake_velo_omie_homolog_raw.projects
