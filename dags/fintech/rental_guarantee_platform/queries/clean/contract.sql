SELECT
    id,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    propose AS id_propose,
    status AS id_status,
    plan AS id_plan,
    maintenant AS id_main_tenant,
    realestate AS id_real_estate,
    realtor AS id_realtor,
    active AS is_active,
    begin AS ts_began,
    done AS ts_done,
    dateinsert AS ts_inserted,
    dateupdate AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.contract
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
