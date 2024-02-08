SELECT
    BIGINT(id_cbsituacaocontrato_int) AS id_customer_history,
    BIGINT(id_geusuario_int) AS id_user,
    codigo_str AS code,
    descricao_str AS description,
    acao_str AS action,
    com_senha_str AS with_password,
    NOW() AS ts_load
FROM datalake_paschoalotto_raw.cbsituacaocontrato
QUALIFY ROW_NUMBER() OVER(PARTITION BY id_cbsituacaocontrato_int ORDER BY DATE(CONCAT(year, "-", month, "-", day)) DESC, ts_load DESC) = 1
