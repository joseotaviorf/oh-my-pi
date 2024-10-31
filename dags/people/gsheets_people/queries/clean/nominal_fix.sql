SELECT
    email AS employee_email,
    sub_diretoria_a AS employee_sub_board,
    diretoria_a AS employee_board,
    vice_presidencia_a AS employee_vice_presidency,
    vertical_a AS employee_vertical,
    hrbp_a AS hrbp,
    ts_load
FROM datalake_gsheets_people_raw.nominal_fix