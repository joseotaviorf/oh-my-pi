WITH deduplicated_leads AS (
    SELECT *
    FROM
        datalake_brokers_supply_processor_clean.lead_3p
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) = 1
),
lead_context AS (
    SELECT
        bcd.id_lead,
        dl.uuid_company,
        bcd.business_context,
        GET_JSON_OBJECT(dl.brokers, '$.createdAt')::TIMESTAMP AS ts_captured,
        -- Here, we want the date in which the batch was sent. In sale, that used to be when the lead was created. Later, rent leads were created
        -- So we need to consider the lead created date for old sale leads, or business_context_created otherwise
        CASE
            WHEN ROW_NUMBER() OVER (PARTITION BY bcd.id_lead ORDER BY bcd.ts_created, bcd.business_context DESC) = 1
                THEN COALESCE(f.ts_created, LEAST(bcd.ts_created, dl.ts_created))
            ELSE
                COALESCE(f.ts_created, bcd.ts_created)
        END AS ts_batch_sent
    FROM
        datalake_brokers_supply_processor.business_context_detail AS bcd
    LEFT JOIN
        deduplicated_leads AS dl
            ON dl.id = bcd.id_lead
    LEFT JOIN
        datalake_brokers_supply_processor.file AS f
            ON bcd.id_file = f.id
),
company_membership AS (
    SELECT
        cs.uuid_company,
        MAX(CASE WHEN ce.event_update = 'Membro' THEN ce.ts_start ELSE NULL END) AS ts_membership_start,
        MIN(lc.ts_batch_sent) AS ts_first_batch
    FROM
        datalake_hubspot.company_events AS ce
    LEFT JOIN
        datalake_company.company_sks AS cs
            ON cs.sk_company = ce.sk_company
    LEFT JOIN
        lead_context AS lc
            ON cs.uuid_company = lc.uuid_company
    WHERE
        ce.event_type = 'Membership Update'
            AND  lc.ts_batch_sent >= ce.ts_start
    GROUP BY ALL
),
recurrency AS (
    SELECT
        lc.id_lead,
        lc.business_context,
        lc.ts_captured,
        lc.ts_batch_sent,
        cm.ts_first_batch,
        CASE
            WHEN lc.ts_batch_sent IS NULL OR cm.ts_first_batch IS NULL THEN 'N/A'
            WHEN lc.ts_batch_sent = cm.ts_first_batch THEN 'FIRST_BATCH'
            WHEN lc.ts_batch_sent < cm.ts_first_batch + INTERVAL 30 DAYS THEN 'FIRST_MONTH_BATCH'
            WHEN lc.ts_captured < cm.ts_first_batch THEN 'COMPLEMENTARY'
            ELSE 'RECURRENT'
        END AS recurrency_type
    FROM
        lead_context AS lc
    LEFT JOIN
        company_membership AS cm
            ON lc.uuid_company = cm.uuid_company
),
houses AS (
    SELECT
        id,
        id_external
    FROM
        datalake_ebdb_clean.house
    WHERE
        id_external IS NOT NULL
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_external ORDER BY dt_creation) = 1
)
SELECT
    l.id,
    sale_bcd.id_partner AS id_sale_partner,
    rent_bcd.id_partner AS id_rent_partner,
    sale_bcd.id_file AS id_sale_file,
    rent_bcd.id_file AS id_rent_file,
    sale_bcd.id_listing AS id_sale_listing,
    rent_bcd.id_listing AS id_rent_listing,
    l.uuid_lead,
    l.uuid_company,
    l.id_real_estate,
    l.id_by_real_estate,
    h.id AS id_house,
    NULLIF(GET_JSON_OBJECT(l.brokers, '$.housePartnerId'), '') AS id_house_partner,
    GET_JSON_OBJECT(l.location, '$.regionId')::BIGINT AS id_region,
    hc.id_company AS id_company_hubspot,
    CASE
        WHEN sale_bcd.id IS NOT NULL THEN hc.id_company
    END AS id_sale_company_hubspot,
    CASE
        WHEN rent_bcd.id IS NOT NULL THEN hc.id_company
    END AS id_rent_company_hubspot,
    FIRST(l.id) OVER(PARTITION BY l.lead_hash ORDER BY l.ts_created) AS id_lead_first_version_global,
    FIRST(l.id) OVER(PARTITION BY l.lead_hash, l.uuid_company ORDER BY l.ts_created) AS id_lead_first_version_by_company,
    NULLIF(GET_JSON_OBJECT(l.owner_agent, '$.externalId'), '') AS id_external_owner_agent,
    NULLIF(GET_JSON_OBJECT(l.owner_agent, '$.personUuid'), '') AS uuid_person_owner_agent,
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
    NULLIF(COALESCE(GET_JSON_OBJECT(l.location, '$.country'), GET_JSON_OBJECT(l.brokers, '$.country')), '') AS country,
    COALESCE(
        NULLIF(GET_JSON_OBJECT(l.location, '$.state'), ''),
        NULLIF(GET_JSON_OBJECT(l.location, '$.stateAcronym'), '')
    ) AS state,
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
    NULLIF(GET_JSON_OBJECT(l.owner_agent, '$.name'), '') AS owner_agent_name,
    NULLIF(GET_JSON_OBJECT(l.owner_agent, '$.email'), '') AS owner_agent_email,
    NULLIF(GET_JSON_OBJECT(l.owner_agent, '$.phone'), '') AS owner_agent_phone,
    NULLIF(GET_JSON_OBJECT(l.owner_agent, '$.relationship'), '') AS owner_agent_relationship,
    FROM_JSON(NULLIF(GET_JSON_OBJECT(l.owner_agent, '$.refusalReason'), '{{}}'), 'map<string, boolean>') AS owner_agent_refusal_reason,
    NULLIF(GET_JSON_OBJECT(l.access, '$.accessType'), '') AS access_type,
    NULLIF(GET_JSON_OBJECT(l.access, '$.authorizationType'), '') AS authorization_type,
    NULLIF(GET_JSON_OBJECT(l.access, '$.occupantType'), '') AS occupant_type,
    NULLIF(GET_JSON_OBJECT(l.access, '$.additionalInfo'), '') AS additional_access_info,
    NULLIF(GET_JSON_OBJECT(l.access, '$.lockerAddress'), '') AS locker_address,
    NULLIF(GET_JSON_OBJECT(l.access, '$.password'), '') AS password,
    l.cnpj,
    sale_bcd.status AS sale_status,
    rent_bcd.status AS rent_status,
    COALESCE(sale_recurrency.recurrency_type, 'N/A') AS sale_recurrency_type,
    COALESCE(rent_recurrency.recurrency_type, 'N/A') AS rent_recurrency_type,
    COALESCE(c_integrator_sale.trade_name, 'N/A') AS sale_integrator_trade_name,
    COALESCE(c_integrator_rent.trade_name, 'N/A') AS rent_integrator_trade_name,
    FROM_JSON(NULLIF(GET_JSON_OBJECT(l.details, '$.installations'), '{{}}'), 'map<string, boolean>') AS installations,
    FROM_JSON(NULLIF(GET_JSON_OBJECT(l.details, '$.appliances'), '{{}}'), 'map<string, boolean>') AS house_appliances,
    FROM_JSON(NULLIF(GET_JSON_OBJECT(l.details, '$.accessibilityItems'), '{{}}'), 'map<string, boolean>') AS accessibility_items,
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
    ROW_NUMBER() OVER(PARTITION BY l.lead_hash ORDER BY l.ts_created) AS version_global,
    ROW_NUMBER() OVER(PARTITION BY l.lead_hash ORDER BY sale_recurrency.ts_batch_sent NULLS LAST, l.ts_created) = 1 AS sale_version_global,
    ROW_NUMBER() OVER(PARTITION BY l.lead_hash ORDER BY rent_recurrency.ts_batch_sent NULLS LAST, l.ts_created) = 1 AS rent_version_global,
    ROW_NUMBER() OVER(PARTITION BY l.lead_hash, l.uuid_company ORDER BY l.ts_created) AS version_by_company,
    ROW_NUMBER() OVER(PARTITION BY l.lead_hash, l.uuid_company ORDER BY sale_recurrency.ts_batch_sent NULLS LAST, l.ts_created) AS sale_version_by_company,
    ROW_NUMBER() OVER(PARTITION BY l.lead_hash, l.uuid_company ORDER BY rent_recurrency.ts_batch_sent NULLS LAST, l.ts_created) AS rent_version_by_company,
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
    ROW_NUMBER() OVER(PARTITION BY l.lead_hash ORDER BY l.ts_created) = 1 AS is_first_version_global,
    ROW_NUMBER() OVER(PARTITION BY l.lead_hash ORDER BY sale_recurrency.ts_batch_sent NULLS LAST, l.ts_created) = 1 AS is_first_sale_version_global,
    ROW_NUMBER() OVER(PARTITION BY l.lead_hash ORDER BY rent_recurrency.ts_batch_sent NULLS LAST, l.ts_created) = 1 AS is_first_rent_version_global,
    ROW_NUMBER() OVER(PARTITION BY l.lead_hash, l.uuid_company ORDER BY l.ts_created) = 1 AS is_first_version_by_company,
    ROW_NUMBER() OVER(PARTITION BY l.lead_hash, l.uuid_company ORDER BY sale_recurrency.ts_batch_sent NULLS LAST, l.ts_created) = 1 AS is_first_sale_version_by_company,
    ROW_NUMBER() OVER(PARTITION BY l.lead_hash, l.uuid_company ORDER BY rent_recurrency.ts_batch_sent NULLS LAST, l.ts_created) = 1 AS is_first_rent_version_by_company,
    ROW_NUMBER() OVER(PARTITION BY l.lead_hash ORDER BY l.ts_created DESC) = 1 AS is_last_version_global,
    ROW_NUMBER() OVER(PARTITION BY l.lead_hash ORDER BY sale_recurrency.ts_batch_sent DESC NULLS LAST, l.ts_created) = 1 AS is_last_sale_version_global,
    ROW_NUMBER() OVER(PARTITION BY l.lead_hash ORDER BY rent_recurrency.ts_batch_sent DESC NULLS LAST, l.ts_created) = 1 AS is_last_rent_version_global,
    ROW_NUMBER() OVER(PARTITION BY l.lead_hash, l.uuid_company ORDER BY l.ts_created DESC) = 1 AS is_last_version_by_company,
    ROW_NUMBER() OVER(PARTITION BY l.lead_hash, l.uuid_company ORDER BY sale_recurrency.ts_batch_sent DESC NULLS LAST, l.ts_created) = 1 AS is_last_sale_version_by_company,
    ROW_NUMBER() OVER(PARTITION BY l.lead_hash, l.uuid_company ORDER BY rent_recurrency.ts_batch_sent DESC NULLS LAST, l.ts_created) = 1 AS is_last_rent_version_by_company,
    MIN(l.ts_created) OVER(PARTITION BY l.lead_hash) AS ts_first_version_created_global,
    MIN(sale_recurrency.ts_batch_sent) OVER(PARTITION BY l.lead_hash) AS ts_first_sale_version_created_global,
    MIN(rent_recurrency.ts_batch_sent) OVER(PARTITION BY l.lead_hash) AS ts_first_rent_version_created_global,
    MIN(l.ts_created) OVER(PARTITION BY l.lead_hash, l.uuid_company) AS ts_first_version_created_by_company,
    MIN(sale_recurrency.ts_batch_sent) OVER(PARTITION BY l.lead_hash, l.uuid_company) AS ts_first_sale_version_created_by_company,
    MIN(rent_recurrency.ts_batch_sent) OVER(PARTITION BY l.lead_hash, l.uuid_company) AS ts_first_rent_version_created_by_company,
    sale_recurrency.ts_batch_sent AS ts_sale_lead_sent,
    rent_recurrency.ts_batch_sent AS ts_rent_lead_sent,
    IF(GET_JSON_OBJECT(l.brokers, '$.createdAt')::TIMESTAMP < '1900-01-01T00:00:00.000+00:00', NULL, GET_JSON_OBJECT(l.brokers, '$.createdAt')::TIMESTAMP) AS ts_house_created,
    IF(GET_JSON_OBJECT(l.brokers, '$.updatedAt')::TIMESTAMP < '1900-01-01T00:00:00.000+00:00', NULL, GET_JSON_OBJECT(l.brokers, '$.updatedAt')::TIMESTAMP) AS ts_house_updated,
    l.ts_created,
    l.ts_updated
FROM
    deduplicated_leads AS l
LEFT JOIN
    datalake_brokers_supply_processor.business_context_detail AS sale_bcd
        ON sale_bcd.id_lead = l.id
        AND sale_bcd.business_context = 'SALE'
LEFT JOIN
    datalake_brokers_supply_processor.business_context_detail AS rent_bcd
        ON rent_bcd.id_lead = l.id
        AND rent_bcd.business_context = 'RENT'
LEFT JOIN
    recurrency AS sale_recurrency
        ON sale_recurrency.id_lead = l.id
        AND sale_recurrency.business_context = 'SALE'
LEFT JOIN
    recurrency AS rent_recurrency
        ON rent_recurrency.id_lead = l.id
        AND rent_recurrency.business_context = 'RENT'
LEFT JOIN
    datalake_hubspot.company AS hc
        ON hc.uuid_company = l.uuid_company
LEFT JOIN
    datalake_company_clean.company AS c_integrator_sale
        ON c_integrator_sale.uuid_company = sale_bcd.id_partner
LEFT JOIN
    datalake_company_clean.company AS c_integrator_rent
        ON c_integrator_rent.uuid_company = rent_bcd.id_partner
LEFT JOIN
    houses AS h
        ON l.uuid_lead = h.id_external