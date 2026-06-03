SELECT
    CustomerId AS id_customer,
    CustomerCode AS id_customer_code,
    Name AS name,
    Activated AS is_activated,
    year,
    month,
    day
FROM
    datalake_olos_dialer_test_raw.Customer
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')