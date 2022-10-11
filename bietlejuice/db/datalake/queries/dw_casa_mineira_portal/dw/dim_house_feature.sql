SELECT
    CAST(house_attr.id_house AS INT) AS sk_house,
    CAST(house_attr.id_attribute AS INT) AS sk_attribute,
    CAST(attr.id_attribute_type AS INT) AS sk_attribute_type,
    COALESCE(CAST(DATE_FORMAT(attr.ts_created, 'yyyyMMdd') AS INT), -1) AS sk_attribute_created_date,
    COALESCE(CAST(DATE_FORMAT(house_attr.ts_created, 'yyyyMMdd') AS INT), -1) AS sk_house_attribute_created_date,
    COALESCE(CAST(DATE_FORMAT(house_attr.ts_deleted, 'yyyyMMdd') AS INT), -1) AS sk_house_attribute_deleted_date,
    attr.attribute_name,
    attr.attribute_full_name,
    attr_type.attribute_name AS attribute_type_name,
    attr_type.attribute_full_name AS attribute_type_full_name,
    attr.ts_created       AS ts_attribute_created,
    house_attr.ts_created AS ts_house_attribute_created,
    house_attr.ts_deleted AS ts_house_attribute_deleted,
    NOW() AS ts_load
FROM   
    datalake_casa_mineira_portal_clean.house_attribute AS house_attr
JOIN
    datalake_casa_mineira_portal_clean.attribute AS attr
        ON attr.id = house_attr.id_attribute
JOIN 
    datalake_casa_mineira_portal_clean.attribute_type AS attr_type
        ON attr_type.id = attr.id_attribute_type 
