SELECT
    id,
    boleto_id AS id_invoice,
    original_boleto_id AS id_original_invoice,
    contract_id AS id_contract,
    third_party_bills_id AS id_third_party_bills,
    digitable_line,
    request_origin,
    status,
    version,
    due_date AS dt_due,
    TRANSFORM(
        original_due_dates,
        x -> DATE_ADD(DATE '1970-01-01', CAST(x AS INT))
    ) AS dt_original_dues,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rental_management_raw.non_payment_report
