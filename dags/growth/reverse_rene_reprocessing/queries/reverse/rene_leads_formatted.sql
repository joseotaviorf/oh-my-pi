
SELECT 
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
        'ownerId', per.id,
        'personUUId', per.uuid_person,
        'name', per.person_name,
        'phoneNumber', ci.contact_info
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
LEFT JOIN 
    datalake_person_clean.contact_info ci 
    ON p.phone_nr = ci.contact_info
LEFT JOIN 
    datalake_person_clean.person per 
    ON ci.id_person = per.id
WHERE  hl.new_id  IS NOT NULL
AND a.street_name != NULL 
OR (a.lat IS NOT NULL AND a.lng IS NOT NULL)