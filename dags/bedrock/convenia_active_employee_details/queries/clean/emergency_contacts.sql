SELECT
    id_employee,
    id AS id_emergency_contacts,
    relation_id as id_relation,
    relation,
    name,
    phone,
    cellphone,
    work_phone,
    email
FROM
    datalake_convenia_details_raw.emergency_contacts
