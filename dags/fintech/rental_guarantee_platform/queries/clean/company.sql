SELECT
    id,
    companyuuid AS uuid_company,
    businessunituuid AS uuid_business_unit,
    productuuid AS uuid_product,
    status,
    version,
    agent_split_fee,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.company

QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
