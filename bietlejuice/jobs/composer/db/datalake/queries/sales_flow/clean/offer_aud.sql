SELECT
    id,
    sales_flow_id AS id_sales_flow,
    reject_reason_id AS id_reject_reason,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    firestore_id AS id_firestore,
    offer_price,
    sale_price,
    preemptive_right,
    discard_reason,
    status,
    sales_flow_id_mod AS mod_id_sales_flow,
    firestore_id_mod AS mod_id_firestore,
    reject_reason_id_mod AS mod_id_reject_reason,
    offer_price_mod AS mod_offer_price,
    sale_price_mod AS mod_sale_price,
    preemptive_right_mod AS mod_preemptive_right,
    discard_reason_mod AS mod_discard_reason,
    status_mod AS mod_status,
    proposal_date_mod AS mod_dt_proposed,
    accepted_at_mod AS mod_ts_accepted,
    validated_at_mod AS mod_ts_validated,
    rejected_at_mod AS mod_ts_rejected,
    discarded_at_mod AS mod_ts_discarded,
    proposal_date AS dt_proposed,
    accepted_at AS ts_accepted,
    validated_at AS ts_validated,
    rejected_at AS ts_rejected,
    discarded_at AS ts_discarded,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.offer_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}