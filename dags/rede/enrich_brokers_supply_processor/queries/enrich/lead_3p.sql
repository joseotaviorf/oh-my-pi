WITH leads AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) AS rw
    FROM
        datalake_brokers_supply_processor_clean.lead_3p
)
SELECT
    l.id,
    l.id_partner,
    l.id_file,
    l.id_listing,
    l.uuid_lead,
    l.id_real_estate,
    l.id_by_real_estate,
    NULLIF(GET_JSON_OBJECT(l.brokers, '$.housePartnerId'), '') AS id_house_partner,
    GET_JSON_OBJECT(l.location, '$.regionId')::BIGINT AS id_region,
    f.id_company_hubspot,
    l.lead_hash,
    NULLIF(GET_JSON_OBJECT(l.brokers, '$.block'), '') AS block,
    NULLIF(GET_JSON_OBJECT(l.brokers, '$.tower'), '') AS tower,
    NULLIF(GET_JSON_OBJECT(l.brokers, '$.infoKey'), '') AS info_key,
    NULLIF(GET_JSON_OBJECT(l.brokers, '$.condominium'), '') AS condominium,
    NULLIF(GET_JSON_OBJECT(l.brokers, '$.houseCategory'), '') AS house_category,
    NULLIF(GET_JSON_OBJECT(l.blueprint, '$.houseType'), '') AS house_type,
    NULLIF(GET_JSON_OBJECT(l.brokers, '$.subTypeHouse'), '') AS house_subtype,
    NULLIF(GET_JSON_OBJECT(l.brokers, '$.constructionYear'), '') AS construction_year,
    NULLIF(GET_JSON_OBJECT(l.details, '$.frontDoorType'), '') AS front_door_type,
    NULLIF(GET_JSON_OBJECT(l.details, '$.description'), '') AS house_description,
    NULLIF(GET_JSON_OBJECT(l.brokers, '$.country'), '') AS country,
    NULLIF(GET_JSON_OBJECT(l.location, '$.state'), '') AS state,
    NULLIF(GET_JSON_OBJECT(l.location, '$.city'), '') AS city,
    NULLIF(GET_JSON_OBJECT(l.location, '$.neighborhood'), '') AS neighborhood,
    NULLIF(GET_JSON_OBJECT(l.location, '$.regionSlug'), '') AS region_slug,
    NULLIF(GET_JSON_OBJECT(l.location, '$.zipCode'), '') AS zip_code,
    NULLIF(GET_JSON_OBJECT(l.location, '$.address'), '') AS address,
    NULLIF(GET_JSON_OBJECT(l.location, '$.number'), '') AS number,
    NULLIF(GET_JSON_OBJECT(l.location, '$.floor'), '') AS floor,
    NULLIF(GET_JSON_OBJECT(l.location, '$.complement'), '') AS complement,
    NULLIF(GET_JSON_OBJECT(l.location, '$.referencePoint'), '') AS reference_point,
    NULLIF(GET_JSON_OBJECT(l.owner, '$.email'), '') AS owner_email,
    NULLIF(GET_JSON_OBJECT(l.owner, '$.name'), '') AS owner_name,
    NULLIF(GET_JSON_OBJECT(l.owner, '$.phone'), '') AS owner_phone,
    NULLIF(GET_JSON_OBJECT(l.owner, '$.personType'), '') AS owner_person_type,
    NULLIF(GET_JSON_OBJECT(l.access, '$.accessType'), '') AS access_type,
    NULLIF(GET_JSON_OBJECT(l.access, '$.authorizationType'), '') AS authorization_type,
    NULLIF(GET_JSON_OBJECT(l.access, '$.occupantType'), '') AS occupant_type,
    NULLIF(GET_JSON_OBJECT(l.access, '$.additionalInfo'), '') AS additional_access_info,
    NULLIF(GET_JSON_OBJECT(l.access, '$.lockerAddress'), '') AS locker_address,
    NULLIF(GET_JSON_OBJECT(l.access, '$.password'), '') AS password,
    l.cnpj,
    l.status,
    CASE
        WHEN f.ts_previous_file_sent_by_agency IS NULL THEN 'FIRST_BATCH'
        WHEN DATE(f.ts_previous_file_sent_by_agency) < GET_JSON_OBJECT(l.brokers, '$.createdAt')::TIMESTAMP THEN 'RECURRENT'
        ELSE 'COMPLEMENTARY'
    END AS recurrency_type,
    FROM_JSON(NULLIF(GET_JSON_OBJECT(l.details, '$.installations'), '{{}}'), 'map<string, boolean>') AS installations,
    FROM_JSON(NULLIF(GET_JSON_OBJECT(l.details, '$.appliances'), '{{}}'), 'map<string, boolean>') AS house_appliances,
    FROM_JSON(NULLIF(GET_JSON_OBJECT(l.details, '$.accessibilityItems'), '{{}}'), 'map<string, boolean>') AS accessibility_items,
    FROM_JSON(NULLIF(status_reason, '{{}}'), 'map<string, string>') AS status_reason,
    FROM_JSON(
        NULLIF(photos, '[]'),
        'array<struct<url: string, description: string>>'
    ) AS photos,
        FROM_JSON(
        NULLIF(GET_JSON_OBJECT(l.administrators, '$.list'), '[]'),
        'array<struct<name: string, email: string, phone: string, mainId: bigint>>'
    ) AS administrators,
    FROM_JSON(
        NULLIF(GET_JSON_OBJECT(l.pricing, '$.iptuList'), '[]'), 
        'array<struct<installmentAmount: int, installmentQuantity: int>>'
    ) AS iptu_installment_informations,
    FROM_JSON(
        NULLIF(GET_JSON_OBJECT(l.pricing, '$.specialConditions'), '[]'),
        'array<string>'
    ) AS special_conditions,
    GET_JSON_OBJECT(l.blueprint, '$.totalArea')::INT AS total_area,
    GET_JSON_OBJECT(l.blueprint, '$.bedrooms')::INT AS bedrooms,
    GET_JSON_OBJECT(l.blueprint, '$.suites')::INT AS suites,
    GET_JSON_OBJECT(l.blueprint, '$.bathrooms')::INT AS bathrooms,
    GET_JSON_OBJECT(l.blueprint, '$.garages')::INT AS garages,
    GET_JSON_OBJECT(l.location, '$.lat')::DECIMAL(11,8) AS latitude,
    GET_JSON_OBJECT(l.location, '$.lng')::DECIMAL(11,8) AS longitude,
    GET_JSON_OBJECT(l.pricing, '$.rent')::INT AS rent_price,
    GET_JSON_OBJECT(l.pricing, '$.salePrice')::INT AS sale_price,
    GET_JSON_OBJECT(l.pricing, '$.condoPrice')::INT AS condo_price,
    l.version,
    GET_JSON_OBJECT(l.access, '$.optedKeysWithAgent')::BOOLEAN AS has_opted_keys_with_agent,
    GET_JSON_OBJECT(l.access, '$.hasRestriction')::BOOLEAN AS has_access_restriction,
    GET_JSON_OBJECT(l.details, '$.isFurnished')::BOOLEAN AS is_furnished,
    GET_JSON_OBJECT(l.details, '$.isPenthouse')::BOOLEAN AS is_penthouse,
    GET_JSON_OBJECT(l.details, '$.isPetFriendly')::BOOLEAN AS is_pet_friendly,
    GET_JSON_OBJECT(l.pricing, '$.iptuNotPaid')::BOOLEAN AS is_iptu_not_paid,
    GET_JSON_OBJECT(l.location, '$.outOfArea')::BOOLEAN AS is_out_of_area,
    GET_JSON_OBJECT(l.brokers, '$.habitat')::BOOLEAN AS is_habitat,
    GET_JSON_OBJECT(l.brokers, '$.balcony')::BOOLEAN AS has_balcony,
    GET_JSON_OBJECT(l.brokers, '$.agencyKey')::BOOLEAN AS has_agency_key,
    GET_JSON_OBJECT(l.brokers, '$.concierge')::BOOLEAN AS has_concierge,
    l.is_sent_to_main,
    GET_JSON_OBJECT(l.brokers, '$.createdAt')::TIMESTAMP AS ts_house_created,
    GET_JSON_OBJECT(l.brokers, '$.updatedAt')::TIMESTAMP AS ts_house_updated,
    l.ts_created,
    l.ts_updated
FROM
    leads AS l
LEFT JOIN
    datalake_brokers_supply_processor.file AS f
        ON l.id_file = f.id
WHERE
    rw = 1