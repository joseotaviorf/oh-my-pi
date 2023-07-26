SELECT
    id,
    propose,
    document,
    type,
    value,
    paid_value,
    due_date    AS ts_due
FROM
    datalake_rental_guarantee_platform_raw.omie_occurrence_legacy
