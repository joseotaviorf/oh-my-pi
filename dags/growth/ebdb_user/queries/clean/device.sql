SELECT
    id,
    arn,
    mobileApp AS mobile_app,
    usuario_id AS id_user,
    token,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created,
    endpointArn AS arn_endpoint,
    mobilePlatform AS mobile_platform,
    appVersion AS app_version,
    environment,
    pwaPublicKey AS pwa_public_key,
    pwaAuth AS pwa_auth
FROM
    datalake_ebdb_raw.device
