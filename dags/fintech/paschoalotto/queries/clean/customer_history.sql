SELECT
    BIGINT(id_cbsituacaocontrato_int) AS id_customer_history,
    BIGINT(id_geusuario_int) AS id_user,
    codigo_str AS contract_status,
    descricao_str AS description,
    CASE
        WHEN acao_str = "0" THEN "Aberto"
        WHEN acao_str = "1" THEN "Fechado"
        WHEN acao_str = "2" THEN "Não Cobra"
        WHEN acao_str = "3" THEN "Satnd by"
        WHEN acao_str = "4" THEN "Jurídico"
        ELSE acao_str
    END AS action,
    context,
    com_senha_str AS with_password,
    NOW() AS ts_load
FROM datalake_paschoalotto_raw.cbsituacaocontrato
QUALIFY ROW_NUMBER() OVER(PARTITION BY id_cbsituacaocontrato_int ORDER BY DATE(CONCAT(year, "-", month, "-", day)) DESC, ts_load DESC) = 1
