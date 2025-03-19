SELECT
    id,
    imovel_id AS id_house,
    supplier_id AS id_supplier,
    rev,
    revtype AS rev_type,
    codigoinstalacao AS installation_code,
    tipo AS type,
    chargingBillType AS type_charging_bill,
    titularidade AS titularity,
    transferRegister AS transfer_register,
    cpftitular AS cpf_holder,
    isInclusaCondominio AS is_condo_included,
    isligado AS is_turned_on,
    transferregister_mod AS mod_transfer_register
FROM
    datalake_ebdb_raw.contaconsumo_aud
