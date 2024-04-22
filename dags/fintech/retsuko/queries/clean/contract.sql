SELECT
    id,
    external_id AS id_external,
    UPPER(country) AS country_code,
    locale AS city,
    version,
    guarantee,
    is_b2b,
    is_rental_paid_in_advance,
    signature_date AS ts_signature,
    guarantee_start_date AS ts_guarantee_started,
    start_period AS ts_period_started,
    start_charge AS ts_charge_started,
    end_charge AS ts_charge_ended
FROM
    datalake_retsuko_raw.contract
