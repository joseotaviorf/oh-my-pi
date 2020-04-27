SELECT
    id as id_condo_amenity,
    nome as name,
    ativo as is_active,
    descricaoCampo1 as first_description_field,
    descricaoCampo2 as second_description_field,
    descricaoCampo3 as third_description_field,
    descricaoCampo4 as fourth_description_field,
    descricaoCampo5 as fifth_description_field,
    atualizadoEm as ts_updated,
    criadoEm as ts_created,
    editavel as is_editable,
    codigo as code,
    slug,
    salesforceCode as salesforce_code
FROM
    datalake_ebdb_raw.instalacao