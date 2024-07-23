SELECT
    cod_login AS id_user,
    cod_pes AS id_person,
    cod_superv AS id_supervisor,
    niv_cod AS user_level,
    NOW() AS ts_load
FROM datalake_webhelp_homolog_raw.login
