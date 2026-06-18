SELECT
    id,
    portability_id AS id_portability,
    condoPayer AS condo_payer,
    condoPaidInAdvance AS is_condo_paid_in_advance,
    rentalPaidInAdvance AS is_rental_paid_in_advance,
    iptuPaidInAdvance AS is_iptu_paid_in_advance,
    homeInsuranceInAdvance AS is_home_insurance_in_advance,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated
FROM
    datalake_ebdb_raw.paymentrules
