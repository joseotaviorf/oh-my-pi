SELECT
    ID AS id_product,
    Descricao AS product_name,
    PerfilDoc AS profile_doc,
    ativo AS is_active,
    DtCadastro AS ts_registration
FROM
    datalake_atta_test_raw.produto
