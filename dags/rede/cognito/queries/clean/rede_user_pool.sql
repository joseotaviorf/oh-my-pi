SELECT
    username AS id_username,
    FILTER(attributes, x -> x.Name = 'custom:companyProfile')[0].Value AS id_company_profile,
    FILTER(attributes, x -> x.Name = 'custom:companyUUId')[0].Value AS uuid_company,
    FILTER(attributes, x -> x.Name = 'custom:personUUId')[0].Value AS uuid_person,
    FILTER(attributes, x -> x.Name = 'name')[0].Value AS name,
    FILTER(attributes, x -> x.Name = 'given_name')[0].Value AS given_name,
    FILTER(attributes, x -> x.Name = 'family_name')[0].Value AS family_name,
    FILTER(attributes, x -> x.Name = 'email')[0].Value AS email,
    FILTER(attributes, x -> x.Name = 'locale')[0].Value AS locale,
    FILTER(attributes, x -> x.Name = 'picture')[0].Value AS picture,
    FROM_JSON(FILTER(attributes, x -> x.Name = 'identities')[0].Value, 'ARRAY<MAP<string, string>>') AS identities,
    UserStatus AS user_status,
    FILTER(attributes, x -> x.Name = 'email_verified')[0].Value AS is_email_verified,
    Enabled AS is_enabled,
    Deleted AS is_deleted,
    UserCreateDate AS ts_created,
    UserLastModifiedDate AS ts_updated,
    year,
    month,
    day
FROM
    datalake_cognito_raw.rede_user_pool
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}