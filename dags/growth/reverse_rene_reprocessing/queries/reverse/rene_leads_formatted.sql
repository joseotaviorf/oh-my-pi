
SELECT distinct
    hl.new_id AS leadId,
    hl.created_at AS createdAt,
    'lead' AS eventType,
    to_json(named_struct(
        'zipcode', a.zip,
        'state', a.state,
        'city', a.city,
        'neighbourhood', a.neighbourhood,
        'street', a.street_name,
        'number', a.house_number,
        'complement', a.complement,
        'region', a.region,
        'lat', a.lat,
        'lng', a.lng,
        'regionSlug', a.region_slug
    )) AS address,
    to_json(named_struct(
        'phoneNumber', p.phone_nr
    )) AS owner,
    to_json(named_struct(
        'area', get_json_object(ac.house_info, '$.area'),
        'iptu', get_json_object(ac.house_info, '$.iptu'),
        'forRent', get_json_object(ac.house_info, '$.forRent'),
        'forSale', get_json_object(ac.house_info, '$.forSale'),
        'rentValue', get_json_object(ac.house_info, '$.rentValue'),
        'saleValue', get_json_object(ac.house_info, '$.saleValue'),
        'condominium', get_json_object(ac.house_info, '$.condominium'),
        'numberRooms', get_json_object(ac.house_info, '$.numberRooms'),
        'numberSuites', get_json_object(ac.house_info, '$.numberSuites'),
        'numberBathrooms', get_json_object(ac.house_info, '$.numberBathrooms')
    )) AS propertyInfo
FROM 
    datalake_rene_descartes_raw.house_lead hl
LEFT JOIN 
    datalake_rene_descartes_raw.address a 
    ON hl.address_id = a.id
LEFT JOIN 
    datalake_rene_descartes_raw.acquisition_misc_data ac 
    ON hl.acquisition_id = ac.id
LEFT JOIN 
    datalake_rene_descartes_raw.phone p 
    ON hl.house_owner_id = p.owner_id
WHERE  hl.new_id  IS NOT NULL
AND a.street_name IS NOT NULL 
OR (a.lat IS NOT NULL AND a.lng IS NOT NULL)