SELECT
    id,
    vendedorResponsavel_id AS id_sales_rep,
    telefone AS phone_number,
    dataCriacao AS ts_created
FROM
    datalake_ebdb_test_raw.AgrupamentoLeadsPorTelefone
