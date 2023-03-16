WITH first_files AS (
    SELECT
        f.id_company_hubspot,
        CASE
            WHEN f.id_company_hubspot IS NULL THEN SPLIT(f.file_name, '_dedup_')[0]
        END AS company_file_name_part,
        bcd.business_context,
        MIN(f.ts_created) AS ts_created
    FROM
        datalake_brokers_supply_processor.business_context_detail AS bcd
    JOIN
        datalake_brokers_supply_processor.file AS f
            ON bcd.id_file = f.id
    GROUP BY
        1,2,3
),
deduplicated_leads AS (
    SELECT *
    FROM
        datalake_brokers_supply_processor_clean.lead_3p
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) = 1
)
SELECT
    l.id,
    COALESCE(l.id_partner, sale_bcd.id_partner, rent_bcd.id_partner) AS id_partner,
    sale_bcd.id_partner AS id_sale_partner,
    rent_bcd.id_partner AS id_rent_partner,
    COALESCE(l.id_file, sale_bcd.id_file, rent_bcd.id_file) AS id_file,
    sale_bcd.id_file AS id_sale_file,
    rent_bcd.id_file AS id_rent_file,
    COALESCE(l.id_listing, sale_bcd.id_listing, rent_bcd.id_listing) AS id_listing,
    sale_bcd.id_listing AS id_sale_listing,
    rent_bcd.id_listing AS id_rent_listing,
    l.uuid_lead,
    l.id_real_estate,
    l.id_by_real_estate,
    NULLIF(GET_JSON_OBJECT(l.brokers, '$.housePartnerId'), '') AS id_house_partner,
    GET_JSON_OBJECT(l.location, '$.regionId')::BIGINT AS id_region,
    COALESCE(f.id_company_hubspot, sale_file.id_company_hubspot, rent_file.id_company_hubspot) AS id_company_hubspot,
    COALESCE(sale_file.id_company_hubspot) AS id_sale_company_hubspot,
    COALESCE(rent_file.id_company_hubspot) AS id_rent_company_hubspot,
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
    COALESCE(l.status, sale_bcd.status, rent_bcd.status) AS status,
    sale_bcd.status AS sale_status,
    rent_bcd.status_reason AS rent_status,
    CASE
        WHEN f.ts_previous_file_sent_by_agency IS NULL THEN 'FIRST_BATCH'
        WHEN f.ts_created < first_file.ts_created + INTERVAL 30 DAYS THEN 'FIRST_MONTH_BATCH'
        WHEN GET_JSON_OBJECT(l.brokers, '$.createdAt')::TIMESTAMP < first_file.ts_created THEN 'COMPLEMENTARY'
        ELSE 'RECURRENT'
    END AS recurrency_type,
    CASE
        WHEN sale_file.ts_created IS NULL THEN 'N/A'
        WHEN sale_file.ts_created = first_sale_file.ts_created THEN 'FIRST_BATCH'
        WHEN sale_file.ts_created < first_sale_file.ts_created + INTERVAL 30 DAYS THEN 'FIRST_MONTH_BATCH'
        WHEN GET_JSON_OBJECT(l.brokers, '$.createdAt')::TIMESTAMP < first_sale_file.ts_created THEN 'COMPLEMENTARY'
        ELSE 'RECURRENT'
    END AS sale_recurrency_type,
    CASE
        WHEN rent_file.ts_created IS NULL THEN 'N/A'
        WHEN rent_file.ts_created = first_rent_file.ts_created THEN 'FIRST_BATCH'
        WHEN rent_file.ts_created < first_rent_file.ts_created + INTERVAL 30 DAYS THEN 'FIRST_MONTH_BATCH'
        WHEN GET_JSON_OBJECT(l.brokers, '$.createdAt')::TIMESTAMP < first_rent_file.ts_created THEN 'COMPLEMENTARY'
        ELSE 'RECURRENT'
    END AS rent_recurrency_type,
    FROM_JSON(NULLIF(GET_JSON_OBJECT(l.details, '$.installations'), '{{}}'), 'map<string, boolean>') AS installations,
    FROM_JSON(NULLIF(GET_JSON_OBJECT(l.details, '$.appliances'), '{{}}'), 'map<string, boolean>') AS house_appliances,
    FROM_JSON(NULLIF(GET_JSON_OBJECT(l.details, '$.accessibilityItems'), '{{}}'), 'map<string, boolean>') AS accessibility_items,
    COALESCE(FROM_JSON(NULLIF(l.status_reason, '{{}}'), 'map<string, string>'), sale_bcd.status_reason) AS status_reason,
    sale_bcd.status_reason AS sale_status_reason,
    rent_bcd.status_reason AS rent_status_reason,
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
    sale_bcd.id IS NOT NULL AS is_for_sale,
    rent_bcd.id IS NOT NULL AS is_for_rent,
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
    deduplicated_leads AS l
LEFT JOIN
    datalake_brokers_supply_processor.file AS f
        ON l.id_file = f.id
LEFT JOIN
    datalake_brokers_supply_processor.file AS first_file
        ON COALESCE(f.id_company_hubspot, SPLIT(f.file_name, '_dedup_')[0]) = COALESCE(first_file.id_company_hubspot, SPLIT(first_file.file_name, '_dedup_')[0])
        AND first_file.ts_previous_file_sent_by_agency IS NULL
LEFT JOIN
    datalake_brokers_supply_processor.business_context_detail AS sale_bcd
        ON sale_bcd.id_lead = l.id
        AND sale_bcd.business_context = 'SALE'
LEFT JOIN
    datalake_brokers_supply_processor.business_context_detail AS rent_bcd
        ON sale_bcd.id_lead = l.id
        AND sale_bcd.business_context = 'RENT'
LEFT JOIN
    datalake_brokers_supply_processor.file AS sale_file
        ON sale_bcd.id_file = sale_file.id
LEFT JOIN
    datalake_brokers_supply_processor.file AS rent_file
        ON rent_bcd.id_file = rent_file.id
LEFT JOIN
    first_files AS first_sale_file
        ON COALESCE(sale_file.id_company_hubspot, SPLIT(sale_file.file_name, '_dedup_')[0]) = COALESCE(first_sale_file.id_company_hubspot, first_sale_file.company_file_name_part)
        AND first_sale_file.business_context = 'SALE'
LEFT JOIN
    first_files AS first_rent_file
        ON COALESCE(rent_file.id_company_hubspot, SPLIT(rent_file.file_name, '_dedup_')[0]) = COALESCE(first_rent_file.id_company_hubspot, first_rent_file.company_file_name_part)
        AND first_rent_file.business_context = 'RENT'