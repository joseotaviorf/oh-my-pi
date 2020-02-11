SELECT
    id as id_info_amenity,
    REV as rev,
    rEVTYPE as rev_type,
    temCaracteristica as has_feature,
    temCaracteristica_MOD as mod_has_feature,
    imovel_id as id_house,
    amenidades_id as id_amenity
FROM
    datalake_ebdb_raw.amenidadesinfo_aud