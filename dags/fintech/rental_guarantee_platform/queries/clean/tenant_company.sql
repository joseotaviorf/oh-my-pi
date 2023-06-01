SELECT
    id,
    companyuuid AS uuid_company,
    version,
    email,
    phone,
    declared_income,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
    FROM
        datalake_rental_guarantee_platform_raw.tenant_company
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
