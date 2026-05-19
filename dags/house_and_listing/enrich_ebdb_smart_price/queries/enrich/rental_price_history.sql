/*
Tracking only prices For Rent.
Sale price is stored in other column
on house_aud.
*/

WITH price_audition AS (
    SELECT
        ha.id_house,
        ha.rev,
        ure.reason,
        ha.rent, 
        COALESCE(LAG(ha.rent) OVER(PARTITION BY ha.id_house ORDER BY ha.rev), -1) AS previous_rent,
        ure.ts_revision
    FROM
        datalake_ebdb_clean.house_aud AS ha
    JOIN
        datalake_ebdb_user.user_revision_entity AS ure
            ON ha.rev = ure.id
    WHERE
        -- We have some tests in ebdb. So in order to remove
        -- them and not impact future analysis, these cases are
        -- being removed here.
        is_for_rent = TRUE 
        AND rent >= 0
)
SELECT
    id_house,
    rev,
    reason AS change_reason,
    previous_rent,
    rent,
    MAX(rev) OVER(PARTITION BY id_house, DATE(ts_revision)) = rev AS is_last_status_of_day,
    ts_revision AS ts_price_started,
    LEAD(ts_revision) OVER(PARTITION BY id_house ORDER BY rev) AS ts_price_ended
FROM
    price_audition
WHERE
    rent <> previous_rent