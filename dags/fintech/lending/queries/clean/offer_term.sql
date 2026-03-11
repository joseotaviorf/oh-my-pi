SELECT
    id,
    uuid,
    sheet_id AS id_sheet,
    base_value_multiplier,
    monthly_interest_rate,
    installments_number,
    created_at AS ts_created
FROM
    datalake_lending_raw.offer_term
