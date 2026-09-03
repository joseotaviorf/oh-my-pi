SELECT
    idsubtipodepropiedad AS id_property_subtype,
    idtipodepropiedad AS id_property_type,
    nombre AS property_subtype_name
FROM
    datalake_zonaprop_raw.subtiposdepropiedad
