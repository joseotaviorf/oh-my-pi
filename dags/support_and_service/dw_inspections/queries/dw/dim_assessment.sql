SELECT
    id_assessment AS sk_assessment,
    source,
    house_supplies,
    key_location,
    key_location_details,
    dt_owner_limit_revision,
    dt_tenant_limit_revision,
    ts_created,
    ts_finished AS ts_finished_local,
    ts_started AS ts_started_local,
    ts_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_inspection_services_clean.assessment
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_assessment ORDER BY ts_updated DESC) = 1
