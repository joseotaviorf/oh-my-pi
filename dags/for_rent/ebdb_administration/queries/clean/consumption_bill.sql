SELECT
    id,
    imovel_id AS id_house,
    supplier_id AS id_supplier,
    endereco_estado_id AS id_state,
    codigoinstalacao AS installation_code,
    tipo AS type,
    chargingBillType AS type_charging_bill,
    titularidade AS titularity,
    transferRegister AS transfer_register,
    cpftitular AS cpf_holder,
    endereco_cep AS cep,
    endereco_logradouro AS address,
    endereco_numero AS number,
    endereco_complemento AS  complement,
    endereco_bairro AS neighborhood,
    endereco_cidade AS city,
    isInclusaCondominio AS is_condo_included,
    isligado AS is_turned_on,
    criadoem AS ts_created,
    atualizadoem AS ts_updated
FROM
    datalake_ebdb_raw.contaconsumo
