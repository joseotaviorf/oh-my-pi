SELECT
    mh.sk_hierarchy_version AS sk_manager_hierarchy,
    mh.person_number,
    mh.person_number_manager,
    mh.name_manager,
    mh.email_manager,
    mh.person_number_l0,
    mh.name_l0,
    mh.email_l0,
    mh.person_number_l1,
    mh.name_l1,
    mh.email_l1,
    mh.person_number_l2,
    mh.name_l2,
    mh.email_l2,
    mh.person_number_l3,
    mh.name_l3,
    mh.email_l3,
    mh.person_number_l4,
    mh.name_l4,
    mh.email_l4,
    mh.person_number_l5,
    mh.name_l5,
    mh.email_l5,
    mh.person_number_l6,
    mh.name_l6,
    mh.email_l6,
    mh.person_number_l7,
    mh.name_l7,
    mh.email_l7,
    mh.person_number_l8,
    mh.name_l8,
    mh.email_l8,
    mh.person_number_l9,
    mh.name_l9,
    mh.email_l9,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    datalake_people.management_hierarchy AS mh
INNER JOIN
    datalake_people.identifier_mapping AS im
        ON mh.assignment_number = im.assignment_number
        AND im.is_person_latest_assignment
        AND im.is_active
        AND NOT im.is_user_test
WHERE
    mh.is_current = TRUE
