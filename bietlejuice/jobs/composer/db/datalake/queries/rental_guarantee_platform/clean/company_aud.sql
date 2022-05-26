SELECT
    id,
    companyuuid AS uuid_company,
    businessunituuid AS uuid_business_unit,
    productuuid AS uuid_product,
    version,
    status,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    companyuuid_mod AS mod_uuid_company,
    status_mod AS mod_status,
    businessunituuid_mod AS mod_uuid_businessunit,
    productuuid_mod AS mod_uuid_product,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.company_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}