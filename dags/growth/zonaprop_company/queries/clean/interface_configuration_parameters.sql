SELECT
    idparameter AS id_parameter,
    idinterface AS id_interface,
    name AS parameter_name,
    value AS parameter_value
FROM
    datalake_zonaprop_raw.interfaceconfigurationparameters
