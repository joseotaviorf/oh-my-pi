SELECT 
    id AS id_card_noting,
    rev,
    revtype as rev_type,
    revend as rev_end,
    buyer_and_seller,
    commitment_closing_transfer,
    negotiation_note,
    buyer_and_seller_mod,
    commitment_closing_transfer_mod,
    negotiation_note_mod,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.card_noting_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}