SELECT
    id,
    sales_flow_id AS id_sales_flow,
    firestore_id AS id_firestore,
    reject_reason_id AS id_reject_reason,
    hub_id AS id_hub,
    offer_price,
    sale_price,
    discard_reason,
    status,
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
    datalake_sales_flow_raw.offer
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}