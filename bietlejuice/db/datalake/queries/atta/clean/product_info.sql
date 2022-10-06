SELECT
    ID AS id_product,
    Descricao AS product_name,
    PerfilDoc AS profile_doc,
    ativo AS is_active,
    DtCadastro AS ts_registration,
    year,
    month,
    day
FROM
     datalake_atta_raw.produto
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
