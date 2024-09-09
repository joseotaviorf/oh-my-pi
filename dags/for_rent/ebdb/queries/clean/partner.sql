SELECT
    id,
    amplitudedeviceid as id_amplitude_device,
    state_id AS id_state,
    companyUUID AS uuid_company,
    name,
    phone,
    cnpj,
    creci,
    email,
    address,
    number,
    complement,
    city,
    neighborhood,
    zipCode AS zip_code,
    type,
    landingUrl AS landing_url,
    tradeName AS trade_name,
    partnershipStartsAt AS ts_partnership_started,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated
FROM
    datalake_ebdb_raw.`Partner`
