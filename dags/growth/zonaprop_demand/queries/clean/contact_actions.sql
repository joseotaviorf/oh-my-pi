SELECT
    idcontactoaccion AS id_contact_action,
    idcontacto AS id_contact,
    idtipoaccion AS id_action_type,
    idorigen AS id_source,
    fecha AS ts_occurred
FROM
    datalake_zonaprop_raw.contactosacciones
