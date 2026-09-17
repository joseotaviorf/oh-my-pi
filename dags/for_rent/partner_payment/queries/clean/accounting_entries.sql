SELECT
    id,
    entry_id AS id_entry,
    city_id AS id_city,
    bill_id AS id_bill,
    version,
    rule,
    amount,
    currency,
    original_amount,
    business_source,
    accrual_year_month,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_partner_payment_raw.accounting_entries
