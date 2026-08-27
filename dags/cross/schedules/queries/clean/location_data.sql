-- Debezium emits io.debezium.data.geometry.Point as struct(x, y, wkb, srid).
-- x is longitude and y is latitude (OGC / PostGIS axis order).
SELECT
    id,
    calendar_id AS id_calendar,
    CAST(location.y AS DOUBLE) AS latitude,
    CAST(location.x AS DOUBLE) AS longitude,
    accepts_visits_on_holidays AS is_accepts_visits_on_holidays,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_schedules_raw.location_data
