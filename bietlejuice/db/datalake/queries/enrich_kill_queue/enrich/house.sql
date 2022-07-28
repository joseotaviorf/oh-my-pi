WITH house AS (
    SELECT
        *,
        ROW_NUMBER() OVER(PARTITION BY id ORDER BY ts_updated DESC) AS row_n
    FROM
        datalake_kill_queue_clean.house
)
SELECT
    id,
    id_main,
    id_owner,
    id_region,
    city,
    complement,
    house_number,
    street_address,
    state,
    version,
    floor,
    rent_price,
    reservation_fee,
    is_reservation_allowed,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    house
WHERE
    row_n = 1