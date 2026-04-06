SELECT DISTINCT
  h.sk_hierarchy,
  h.sk_assignment_leadership_order_0,
  h.sk_assignment_leadership_order_1,
  h.sk_assignment_leadership_order_2,
  h.sk_assignment_leadership_order_3,
  h.sk_assignment_leadership_order_4,
  h.sk_assignment_leadership_order_5,
  h.sk_assignment_leadership_order_6,
  h.sk_assignment_leadership_order_7,
  h.sk_assignment_leadership_order_8,
  h.sk_assignment_leadership_order_9,
  wi0.assignment_number AS assignment_number_leadership_0,
  wi1.assignment_number AS assignment_number_leadership_1,
  wi2.assignment_number AS assignment_number_leadership_2,
  wi3.assignment_number AS assignment_number_leadership_3,
  wi4.assignment_number AS assignment_number_leadership_4,
  wi5.assignment_number AS assignment_number_leadership_5,
  wi6.assignment_number AS assignment_number_leadership_6,
  wi7.assignment_number AS assignment_number_leadership_7,
  wi8.assignment_number AS assignment_number_leadership_8,
  wi9.assignment_number AS assignment_number_leadership_9,
  wi0.name AS name_leadership_0,
  wi1.name AS name_leadership_1,
  wi2.name AS name_leadership_2,
  wi3.name AS name_leadership_3,
  wi4.name AS name_leadership_4,
  wi5.name AS name_leadership_5,
  wi6.name AS name_leadership_6,
  wi7.name AS name_leadership_7,
  wi8.name AS name_leadership_8,
  wi9.name AS name_leadership_9,
  wi0.work_email AS email_leadership_0,
  wi1.work_email AS email_leadership_1,
  wi2.work_email AS email_leadership_2,
  wi3.work_email AS email_leadership_3,
  wi4.work_email AS email_leadership_4,
  wi5.work_email AS email_leadership_5,
  wi6.work_email AS email_leadership_6,
  wi7.work_email AS email_leadership_7,
  wi8.work_email AS email_leadership_8,
  wi9.work_email AS email_leadership_9,
  NOW() AS ts_load
FROM
  datalake_hr_system.hierarchy_ids AS h
LEFT JOIN
  datalake_people.identifier_mapping AS wi0
    ON wi0.id_period_of_service = h.sk_assignment_leadership_order_0
LEFT JOIN
  datalake_people.identifier_mapping AS wi1
    ON wi1.id_period_of_service = h.sk_assignment_leadership_order_1
LEFT JOIN
  datalake_people.identifier_mapping AS wi2
    ON wi2.id_period_of_service = h.sk_assignment_leadership_order_2
LEFT JOIN
  datalake_people.identifier_mapping AS wi3
    ON wi3.id_period_of_service = h.sk_assignment_leadership_order_3
LEFT JOIN
  datalake_people.identifier_mapping AS wi4
    ON wi4.id_period_of_service = h.sk_assignment_leadership_order_4
LEFT JOIN
  datalake_people.identifier_mapping AS wi5
    ON wi5.id_period_of_service = h.sk_assignment_leadership_order_5
LEFT JOIN
  datalake_people.identifier_mapping AS wi6
    ON wi6.id_period_of_service = h.sk_assignment_leadership_order_6
LEFT JOIN
  datalake_people.identifier_mapping AS wi7
    ON wi7.id_period_of_service = h.sk_assignment_leadership_order_7
LEFT JOIN
  datalake_people.identifier_mapping AS wi8
    ON wi8.id_period_of_service = h.sk_assignment_leadership_order_8
LEFT JOIN
  datalake_people.identifier_mapping AS wi9
    ON wi9.id_period_of_service = h.sk_assignment_leadership_order_9