SELECT
    im.id_person AS sk_employee,
    im.person_number,
    COALESCE(im.display_name, im.full_name) AS name,
    im.work_email,
    NOW() AS ts_load
FROM
    datalake_people.identifier_mapping AS im
WHERE
    NOT im.is_user_test
    AND im.is_person_latest_assignment
