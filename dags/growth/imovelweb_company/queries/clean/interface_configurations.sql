SELECT
    idinterface AS id_interface,
    idpais AS id_country,
    defaultidempresa AS default_id_company,
    defaultidusuario AS default_id_user,
    idintegrador AS id_integrator,
    classname AS class_name,
    nombre AS interface_name,
    parametros AS parameters,
    procesador AS processor_code,
    rangohorasejecucioninicio AS execution_hour_range_start,
    rangohorasejecucionfin AS execution_hour_range_end,
    minutosentreejecuciones AS minutes_between_executions,
    descargarimagenes AS is_image_download_enabled,
    habilitado AS is_enabled,
    justcheck AS is_check_only,
    isonline AS is_online
FROM
    datalake_imovelweb_raw.interfaceconfigurations
