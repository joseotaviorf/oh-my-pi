SELECT
    CTCRTID AS id_court,
    CTNAME AS court_name,
    CTADDR1 AS address_line1,
    CTADDR2 AS address_line2,
    CTCITY AS city,
    CTSTATE AS state,
    CTZIP AS zip_code,
    CTCOUNTRY AS country,
    CTCNTNAME AS contact_name,
    CTPHONE1 AS phone_number1,
    CTPHONE2 AS phone_number2,
    CTEMAIL AS email_address,
    CTURL AS url,
    NOW() AS ts_load
FROM datalake_cyber_legal_homolog_raw.court
