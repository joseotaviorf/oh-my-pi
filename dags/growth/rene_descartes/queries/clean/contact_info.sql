SELECT
    id_contact,
    person_id AS id_person,
    name,
    channels,
    linked_devices,
    ts_created,
    ts_updated,
    YEAR(ts_updated) AS year,
    MONTH(ts_updated) AS month,
    DAY(ts_updated) AS day
FROM
    datalake_rene_descartes_raw.contact_info
