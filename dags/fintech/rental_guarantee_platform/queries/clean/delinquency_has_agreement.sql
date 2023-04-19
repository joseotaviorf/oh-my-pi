SELECT
    delinquency_id AS id_delinquency,
    agreement_id AS id_agreement,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.delinquency_has_agreement

QUALIFY
    ROW_NUMBER() OVER (PARTITION BY delinquency_id, agreement_id ORDER BY created_at DESC) = 1