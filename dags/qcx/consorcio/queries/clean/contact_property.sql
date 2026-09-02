-- EAV grain: PHONE in masked_property_value, every other key in property_value.
SELECT
    id,
    contact_id AS id_contact,
    property_key,
    CASE
        WHEN property_key IN ('PHONE') THEN NULL
        ELSE property_value
    END AS property_value,
    CASE
        WHEN property_key IN ('PHONE') THEN property_value
    END AS masked_property_value,
    created_at AS ts_created
FROM
    datalake_consorcio_raw.contact_property
