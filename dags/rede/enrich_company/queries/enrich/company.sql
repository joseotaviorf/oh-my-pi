WITH listing_ownership AS (
    SELECT
        hlr.id_related AS uuid_company,
        COUNT(DISTINCT hlr.id_house) AS houses_currently_owned,
        COUNT_IF(lbc.business_context = 'SALE') AS sale_listings_currently_owned,
        COUNT_IF(lbc.business_context = 'RENT') AS rent_listings_currently_owned
    FROM
        datalake_ebdb_clean.house_listing_relation AS hlr
    JOIN
        datalake_ebdb_clean.listing_business_context AS lbc
            ON lbc.id = hlr.id_listing_business_context
    WHERE
        hlr.related_as = 'LISTING_OWNER'
        AND hlr.source_type = 'COMPANY_REF'
    GROUP BY 1
),
lead_3p_ownership AS (
    SELECT
        l.uuid_company,
        COUNT(DISTINCT l.id) AS leads_currently_owned,
        COUNT(DISTINCT IF(bcd.business_context = 'SALE', l.id, NULL)) AS sale_leads_currently_owned,
        COUNT(DISTINCT IF(bcd.business_context = 'RENT', l.id, NULL)) AS rent_leads_currently_owned
    FROM
        datalake_brokers_supply_processor_clean.lead_3p AS l
    JOIN
        datalake_brokers_supply_processor_clean.business_context_detail AS bcd
            ON l.id = bcd.id_lead
    GROUP BY 1
),
company_document AS (
    SELECT
        COALESCE(c.uuid_company, d.uuid_company) AS uuid_company,
        CASE
            WHEN a.country IN ('Brasil', 'Brazil', 'BR')
            OR a.country IS NULL THEN NULLIF(REGEXP_REPLACE(identification_number, '[^0-9]', ''), '')
        END AS cnpj,
        CASE
            WHEN a.country IN ('México', 'Mexico', 'MX') THEN NULLIF(REGEXP_REPLACE(identification_number, '[^0-9A-Za-z]', ''), '')
        END AS rfc,
        NULLIF(REGEXP_REPLACE(identification_number, '[^0-9A-Za-z]', ''), '') AS document,
        CASE d.status
            WHEN 'ACTIVE' THEN 0
            ELSE 1
        END AS document_status_preference
    FROM
        datalake_company_clean.document AS d
    LEFT JOIN
        datalake_company_clean.company_document AS cd
            ON cd.id_document = d.id
    LEFT JOIN
        datalake_company_clean.company AS c
            ON c.id = cd.id_company
    LEFT JOIN
        datalake_company_clean.address AS a
            ON c.uuid_company = a.uuid_company
    WHERE
        document_type IN ('CNPJ', 'RFC')
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY c.uuid_company ORDER BY document_status_preference, d.ts_updated DESC) = 1
),
products AS (
    SELECT
        id_company,
        MAX(id_product = 1) AS has_rental_guarantee_product,
        MAX(id_product IN (27, 30, 31)) AS has_rede_product
    FROM
        datalake_company_clean.company_product
    GROUP BY
        id_company
)
SELECT
    c.id AS id_company,
    c.id_parent AS id_parent_company,
    c.uuid_company,
    c.company_name,
    c.trade_name,
    c.company_type,
    cd.cnpj,
    cd.rfc,
    cd.document,
    c.status,
    a.country,
    COALESCE(s.name, a.state) AS state,
    COALESCE(s.abbreviation, a.state) AS state_abbreviation,
    a.city,
    a.neighborhood,
    a.public_area,
    a.zip_code,
    a.number,
    NULLIF(TRIM(a.complement), '') AS complement,
    COALESCE(has_rede_product, FALSE) AS has_rede_product,
    COALESCE(has_rental_guarantee_product, FALSE) AS has_rental_guarantee_product,
    COALESCE(lo.houses_currently_owned, 0) AS houses_currently_owned,
    COALESCE(lo.sale_listings_currently_owned, 0) AS sale_listings_currently_owned,
    COALESCE(lo.rent_listings_currently_owned, 0) AS rent_listings_currently_owned,
    COALESCE(l3o.leads_currently_owned, 0) AS leads_currently_owned,
    COALESCE(l3o.sale_leads_currently_owned, 0) AS sale_leads_currently_owned,
    COALESCE(l3o.rent_leads_currently_owned, 0) AS rent_leads_currently_owned,
    c.ts_created,
    c.ts_updated
FROM
    datalake_company_clean.company AS c
LEFT JOIN
    datalake_company_clean.address AS a
        ON c.uuid_company = a.uuid_company
LEFT JOIN
    listing_ownership AS lo
        ON c.uuid_company = lo.uuid_company
LEFT JOIN
    lead_3p_ownership AS l3o
        ON c.uuid_company = l3o.uuid_company
LEFT JOIN
    datalake_ebdb_clean.state AS s
        ON s.abbreviation = a.state
        OR s.name = a.state
LEFT JOIN
    company_document AS cd
        ON cd.uuid_company = c.uuid_company
LEFT JOIN
    products AS p
        ON p.id_company = c.id
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY c.uuid_company ORDER BY c.ts_updated DESC) = 1
