SELECT
    ID           AS id,
    IDUsuCad     AS id_registration_user,
    Categoria    AS category,
    Descricao    AS category_description,
    DtCadastro   AS ts_registration

FROM
    datalake_atta_test_raw.parceiro_categoria
