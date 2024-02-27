SELECT
    BIGINT(id_geusuario_int) AS id_user,
    nomelogin_str AS login_name,
    nomecompleto_str AS full_name,
    NOW() ts_load
FROM datalake_paschoalotto_raw.geusuario
