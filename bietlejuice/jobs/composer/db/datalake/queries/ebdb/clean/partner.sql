SELECT
    id,
    amplitudedeviceid as id_amplitude_device,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created,
    name,
    phone,
    partnershipStartsAt AS ts_partnership_started,
    cnpj,
    creci,
    email,
    landingUrl AS landing_url,
    zipCode AS zip_code,
    address,
    complement,
    number,
    neighborhood,
    city,
    state_id AS id_state,
    tradeName AS trade_name,
    type
FROM
    datalake_ebdb_raw.`Partner`
