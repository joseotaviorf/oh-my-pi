SELECT
    id,
    partner_id AS id_partner,
    user_id AS id_user,
    type,
    status,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created
FROM
    datalake_ebdb_test_raw.`PartnerAgent`
