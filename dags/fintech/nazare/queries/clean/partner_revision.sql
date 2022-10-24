SELECT
    `id` AS id_partner,
    revision,
    brokerage,
    quintoandar_administration_fee,
    demand_partner_fee,
    supply_partner_fee,
    invalidated_at AS ts_invalidated,
    created_at AS ts_created
FROM
    datalake_nazare_raw.partner_revision
