SELECT
    id,
    person_id AS id_person,
    sale_id AS id_sale,
    type AS person_type
FROM
    datalake_monopoly_raw.person_sale