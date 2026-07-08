SELECT
    id_contact,
    person_id AS id_person,
    name,
    contact_info,
    ts_created,
    ts_updated,
    YEAR(ts_updated) AS year,
    MONTH(ts_updated) AS month,
    DAY(ts_updated) AS day
FROM
    datalake_rene_descartes_raw.lead_contact_info
