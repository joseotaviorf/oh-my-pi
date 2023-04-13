SELECT
    id,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    propose AS id_propose,
    status AS id_status,
    company_plan AS id_company_plan,
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

QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY dateupdate DESC) = 1
