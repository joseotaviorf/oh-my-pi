SELECT
    idtipodepropiedad AS id_property_type,
    idcategoriatipodepropiedad AS id_property_type_category,
    nombre AS property_type_name
FROM
    datalake_realestate_raw.tiposdepropiedad
