SELECT
    id,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    propose AS id_propose,
    status AS id_status,
    maintenant AS id_main_tenant,
    realestate AS id_real_estate,
    realtor AS id_realtor,
    current_payment_method,
    active AS is_active,
    begin AS ts_began,
    done AS ts_done,
    next_renewal_date AS dt_next_renewal,
    dateinsert AS ts_inserted,
    dateupdate AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.contract

QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY dateupdate DESC) = 1
