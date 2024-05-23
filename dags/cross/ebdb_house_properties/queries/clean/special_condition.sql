SELECT
    id,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created,
    optedInAt AS ts_opted_in,
    optedOutAt AS ts_opted_out,
    imovel_id AS id_house,
    specialConditionType AS special_condition_type,
    expirationDate AS ts_expired,
    specialConditionStatus AS special_condition_status,
    partner_id AS id_partner
FROM
    datalake_ebdb_raw.`specialcondition`
