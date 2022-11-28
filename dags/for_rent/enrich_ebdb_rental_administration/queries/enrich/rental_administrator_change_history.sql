SELECT 
    aud.id_rental_administrator_change_request,
    aud.id_house,
    COALESCE(ch.country_code, 'Undefined') AS country_code,
    aud.old_rental_administrator AS previous_rental_administrator,
    aud.new_rental_administrator AS rental_administrator,
    aud.ts_created AS ts_started,
    LEAD(aud.ts_created) OVER(PARTITION BY aud.id_house ORDER BY aud.ts_created) AS ts_ended
FROM 
    datalake_ebdb_clean.rental_administrator_change_request_aud AS aud
LEFT JOIN
    datalake_ebdb_country.house AS ch
        ON ch.id_house = aud.id_house
WHERE 
    aud.mod_migrated IS TRUE