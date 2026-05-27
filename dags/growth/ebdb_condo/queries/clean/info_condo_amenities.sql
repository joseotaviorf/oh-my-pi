SELECT
    id as id_info_condo_amenity,
    campo1 as is_first_field,
    campo2 as is_second_field,
    campo3 as is_third_field,
    campo4 as is_fourth_field,
    campo5 as is_fifth_field,
    temCaracteristica as has_characteristic,
    imovel_id as id_house,
    instalacao_id as id_condo_amenities,
    atualizadoEm as ts_updated,
    criadoEm as ts_created
FROM
    datalake_ebdb_raw.instalacaoinfo