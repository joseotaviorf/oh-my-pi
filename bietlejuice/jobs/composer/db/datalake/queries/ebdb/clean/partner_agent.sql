SELECT
    id,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created,
    status,
    partner_id AS id_partner,
    user_id AS id_user,
    type
FROM
    datalake_ebdb_raw.`PartnerAgent`
