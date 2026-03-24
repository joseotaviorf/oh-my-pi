SELECT
    DispositionId AS id_disposition,
    DispositionPlanId AS id_disposition_plan,
    DispositionTypeId AS id_disposition_type,
    DispositionCode AS disposition_code,
    BussinesSuccess AS business_success,
    CustomerFinisher AS customer_finisher,
    PhoneFinisher AS phone_finisher,
    year,
    month,
    day
FROM
    datalake_olos_dialer_raw.DispositionDetail
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')