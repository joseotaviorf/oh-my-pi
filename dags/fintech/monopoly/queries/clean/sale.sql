SELECT
    id,
    external_offer_id AS id_external_offer,
    current_revision,
    created_at AS ts_created
FROM
    datalake_monopoly_raw.sale