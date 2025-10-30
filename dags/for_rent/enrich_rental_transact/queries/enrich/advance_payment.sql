WITH advance_payment_with_offer AS (
    SELECT
        ap_aud.id,
        ap_aud.uuid_advance_payment,
        ap_aud.id_house_external,
        ap_aud.id_tenant_external,
        ap_aud.id_owner_external,
        ap_aud.uuid_offer,
        offer.id AS id_offer,
        ap_aud.rev,
        rev_info.ts_rev,
        ap_aud.revend,
        revend_info.ts_rev as ts_revend,
        ap_aud.revtype,
        ap_aud.status,
        ap_aud.rejection_reason,
        ap_aud.payment_percentage,
        ap_aud.payment_amount,
        ap_aud.ts_created,
        ap_aud.ts_updated,
        ap_aud.ts_expires,
        ap_aud.ts_cancelled,
        ap_aud.mod_status,
        ap_aud.mod_ts_expires,
        ap_aud.mod_payment_percentage,
        ap_aud.mod_payment_amount,
        ap_aud.mod_rejection_reason,
        ap_aud.mod_id_tenant_external,
        ap_aud.mod_id_owner_external,
        ap_aud.mod_ts_cancelled        
    FROM
        datalake_rental_transact_clean.advance_payment_aud AS ap_aud
    JOIN
        datalake_rental_transact_clean.rev_info AS rev_info
            ON ap_aud.rev = rev_info.rev
    JOIN
        datalake_rental_transact_clean.rev_info AS revend_info
            ON ap_aud.revend = revend_info.rev
    LEFT JOIN
        datalake_rental_transact_clean.offer AS offer
            ON ap_aud.uuid_offer = offer.uuid_offer
)
SELECT
    id,
    uuid_advance_payment,
    id_house_external,
    id_tenant_external,
    id_owner_external,
    uuid_offer,
    id_offer,
    rev,
    ts_rev,
    revend,
    ts_revend,
    revtype,
    status,
    rejection_reason,
    payment_percentage,
    payment_amount,
    ts_created,
    ts_updated,
    ts_expires,
    ts_cancelled,
    mod_status,
    mod_ts_expires,
    mod_payment_percentage,
    mod_payment_amount,
    mod_rejection_reason,
    mod_id_tenant_external,
    mod_id_owner_external,
    mod_ts_cancelled,    
    YEAR(ts_rev) AS year,
    MONTH(ts_rev) AS month,
    DAY(ts_rev) AS day
FROM
    advance_payment_with_offer
