SELECT
    numero_centro_de_custo AS id_cost_center,
    departamento AS department,
    centro_de_custo_short AS cost_center_short,
    centro_de_custo AS cost_center,
    sub_diretoria AS sub_board,
    diretoria AS board,
    vice_presidencia AS vice_presidency,
    vertical,
    status_centro_de_custo AS cost_center_status,
    business,
    product,
    hrbp,
    codigo_cc_long AS cost_center_code_description,
    ts_load
FROM datalake_gsheets_people_raw.cost_center_hierarchy