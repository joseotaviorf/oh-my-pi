SELECT
    ID AS id_provider,
    Nome AS provider_name,
    Descricao AS provider_description,
    Ativo AS is_active,
    TIMESTAMP(DtCadastro) AS ts_created
FROM
    datalake_atta_test_raw.fornecedores
