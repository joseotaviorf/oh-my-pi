SELECT
    idaviso AS id_listing,
    idinterface AS id_interface,
    idempresa AS id_company,
    idpais AS id_country,
    idinterfacerun AS id_interface_run,
    claveInterface AS interface_key,
    contenthash AS content_hash,
    imageshash AS images_hash,
    accion AS action_code,
    overridemanualchanges AS is_manual_override,
    habilitado AS is_enabled,
    fechaultimasincronizacion AS ts_last_synced,
    fechamodificacionmanual AS ts_manually_updated,
    fechaactualizacionpendiente AS ts_update_pending,
    fechaprocesamientomultimedia AS ts_media_processed,
    fechabaja AS ts_deactivated
FROM
    datalake_zonaprop_raw.interfaceavisodata
