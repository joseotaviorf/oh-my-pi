SELECT
    id,
    token,
    firstSixDigits AS first_six_digits,
    lastFourDigits AS last_four_digits,
    holderName AS holder_name,
    holderDocument AS holder_document,
    brand,
    expirationMonth AS expiration_month,
    expirationYear AS expiration_year
FROM
    datalake_wall_street_raw.creditcard
