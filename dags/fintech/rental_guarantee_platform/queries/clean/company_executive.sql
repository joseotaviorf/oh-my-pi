SELECT
    id,
    personuuid AS uuid_person,
    companyuuid AS uuid_company,
    version,
    userinsert AS user_insert,
    active AS is_active,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.company_executive
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
