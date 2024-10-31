SELECT 
    CAST(id AS BIGINT) AS id,
    agreement_payment_id AS id_agreement_payment,
    delinquency_id AS id_delinquency,
    delinquency_paid_amount,
    interest,
    fine,
    late_fee,
    version,
    condition,
    paid_date AS dt_paid,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM 
    datalake_rental_guarantee_platform_raw.delinquency_accounting
