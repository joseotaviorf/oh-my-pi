SELECT 
    id AS id_card_noting,
    buyer_and_seller,
    commitment_closing_transfer,
    negotiation_note,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.card_noting
