SELECT
   maps.house_id AS id_house,
   id_service,
   maps.weight,
   service_version,
   year,
   month,
   day
FROM (
    SELECT
       id_service,
       EXPLODE(FROM(inputs, "Struct<house_maps: Array<Struct<house_id: LONG, weight: DOUBLE>>>").house_maps) AS maps,
       service_version,
       year,
       month,
       day
    FROM
       datalake_emlio_clean.emlio_logs 
    WHERE
       year = {year}
       AND month = {month}
       AND day = {day}
       AND id_service = 'billboard'
)