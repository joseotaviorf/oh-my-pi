SELECT
    id,
    externalId AS id_external,
    acquireId AS id_acquire,
    acquireTid AS id_acquire_transaction,
    REV AS rev,
    REVTYPE AS rev_type,
    REVEND AS rev_end,
    acquire,
    chargeStatus AS charge_status,
    acquireChargeStatus AS acquire_charge_status,
    acquireAuthCode AS acquire_auth_code,
    acquireNsu AS acquire_nsu,
    paidAt AS ts_paid,
    lastUpdate AS ts_updated
FROM
    datalake_wall_street_raw.charge_aud
