SELECT
    idavisocaracteristica AS id_listing_feature,
    idaviso AS id_listing,
    idcaracteristica AS id_feature,
    idopcion AS id_feature_option,
    valor AS feature_value
FROM
    datalake_imovelweb_raw.avisoscaracteristicas
