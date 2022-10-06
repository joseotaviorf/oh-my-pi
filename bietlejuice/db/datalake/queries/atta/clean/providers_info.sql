SELECT
    ID AS id_provider,
    Nome AS provider_name,
    Descricao AS provider_description,
    Ativo AS is_active,
    TIMESTAMP(DtCadastro) AS ts_created,
    year,
    month,
    day
FROM
    datalake_atta_raw.fornecedores
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
