SELECT
    asn.id_person AS sk_employee,
    im.person_number,
    im.name AS name,
    im.work_email,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    datalake_people.assignment_snapshots AS asn
INNER JOIN
    datalake_people.identifier_mapping AS im
        ON asn.id_person = im.id_person
        AND NOT im.is_user_test
        AND im.is_person_latest_assignment
WHERE
    asn.is_current_for_employee
    AND asn.is_active
