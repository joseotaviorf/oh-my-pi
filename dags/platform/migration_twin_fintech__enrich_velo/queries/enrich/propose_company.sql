
WITH address AS (
    SELECT
        a.*
    FROM
        datalake_rental_guarantee_platform_clean.tenant_company AS c
    LEFT JOIN
        datalake_company_clean.address AS a
            ON c.uuid_company = a.uuid_company
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY c.id ORDER BY a.ts_updated DESC) = 1
),
company_info AS (
    SELECT
        comp.*
    FROM
        datalake_rental_guarantee_platform_clean.tenant_company AS c
    LEFT JOIN
        datalake_company_clean.company AS comp
            ON c.uuid_company = comp.uuid_company
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY c.id ORDER BY comp.ts_updated DESC) = 1
)

SELECT DISTINCT
    tc.id AS id_company,
    comp.trade_name AS company_name,
    a.public_area AS street,
    a.`number`,
    a.complement,
    a.neighborhood,
    a.city,
    COALESCE(st.abbreviation, IF(a.state = '', NULL, UPPER(a.state))) AS state,
    ct.code AS country_code,
    a.zip_code AS zipcode,
    d.identification_number AS cnpj,
    FALSE AS is_legacy,
    tc.ts_created,
    tc.ts_updated
FROM
    datalake_rental_guarantee_platform_clean.tenant_company AS tc
LEFT JOIN
    company_info AS comp
        ON tc.uuid_company = comp.uuid_company
LEFT JOIN
    address AS a
        ON tc.uuid_company = a.uuid_company
LEFT JOIN
    datalake_company_clean.document AS d
        ON tc.uuid_company = d.uuid_company
        AND d.document_type = 'CNPJ'
LEFT JOIN
    datalake_ebdb_clean.country AS ct
        ON IF(REPLACE(a.country, '\'', '') = '', NULL, UPPER(REPLACE(a.country, '\'', ''))) = UPPER(ct.name)
LEFT JOIN
    datalake_ebdb_clean.state AS st
        ON UPPER(a.state) = UPPER(st.name)
        AND ct.id = st.id_country
