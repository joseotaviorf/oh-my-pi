SELECT
    id AS id_special_condition,
    REV AS rev,
    REVTYPE AS rev_type,
    optedInAt AS ts_opted_in,
    optedOutAt AS ts_opted_out,
    specialConditionType AS special_condition_type,
    imovel_id AS id_house,
    expirationDate AS ts_expired,
    specialConditionStatus AS special_condition_status,
    specialConditionStatus_MOD AS mod_special_condition_status,
    optedInAt_MOD AS mod_ts_opted_in,
    optedOutAt_MOD AS mod_ts_opted_out,
    expirationDate_MOD AS mod_ts_expired,
    partner_id AS id_partner,
    partner_MOD AS mod_partner
FROM
    datalake_ebdb_raw.`specialcondition_aud`