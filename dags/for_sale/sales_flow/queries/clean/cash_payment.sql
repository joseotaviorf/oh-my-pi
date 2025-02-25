SELECT
    id AS id_cash_payment,
    payment_id AS id_payment,
    partner_notary,
    status_notary_notes,
    crn_details,
    status_fgts,
    crn_started_at AS ts_crn_started,
    crn_returned_at AS ts_crn_returned,
    crn_ended_at AS ts_crn_ended,
    draft_fgts_started_at AS ts_draft_fgts_started,
    draft_fgts_ended_at AS ts_draft_fgts_ended,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.cash_payment
