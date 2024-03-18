SELECT
    id,
    customer AS id_customer,
    propose AS id_propose,
    dateinsert AS ts_inserted,
    dateupdate AS ts_updated
FROM
    datalake_velo_raw.customer_propose
