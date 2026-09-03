SELECT
    idinterfaceempresa AS id_interface_company,
    idinterface AS id_interface,
    idpais AS id_country,
    idempresa AS id_company,
    idempresaexterna AS id_external_company,
    idusuarioempresa AS id_company_user,
    procesador AS processor_code,
    pausestatus AS pause_status,
    habilitado AS is_enabled,
    fechaalta AS ts_created,
    fechabaja AS ts_deactivated
FROM
    datalake_realestate_raw.interfaceempresas
