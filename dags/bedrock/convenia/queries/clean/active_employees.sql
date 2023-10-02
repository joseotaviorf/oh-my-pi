SELECT
    id,
    driver_license_id as id_driver_license,
    name,
    last_name,
    email,
    intern,
    foreign,
    source,
    driver_license_number,
    driver_license_category,
    driver_license_emission_date as dt_driver_license_emission,
    driver_license_validate_date as dt_driver_license_validation,
    dt_hiring
FROM
    datalake_convenia_raw.active_employees
