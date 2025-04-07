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
  wi0.full_name AS full_name_leadership_0,
  wi1.full_name AS full_name_leadership_1,
  wi2.full_name AS full_name_leadership_2,
  wi3.full_name AS full_name_leadership_3,
  wi4.full_name AS full_name_leadership_4,
  wi5.full_name AS full_name_leadership_5,
  wi6.full_name AS full_name_leadership_6,
  wi7.full_name AS full_name_leadership_7,
  wi8.full_name AS full_name_leadership_8,
  wi9.full_name AS full_name_leadership_9,
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
  datalake_hr_system.employee_ids AS wi0
    ON wi0.id_period_of_service = h.sk_assignment_leadership_order_0
LEFT JOIN
  datalake_hr_system.employee_ids AS wi1
    ON wi1.id_period_of_service = h.sk_assignment_leadership_order_1
LEFT JOIN
  datalake_hr_system.employee_ids AS wi2
    ON wi2.id_period_of_service = h.sk_assignment_leadership_order_2
LEFT JOIN
  datalake_hr_system.employee_ids AS wi3
    ON wi3.id_period_of_service = h.sk_assignment_leadership_order_3
LEFT JOIN
  datalake_hr_system.employee_ids AS wi4
    ON wi4.id_period_of_service = h.sk_assignment_leadership_order_4
LEFT JOIN
  datalake_hr_system.employee_ids AS wi5
    ON wi5.id_period_of_service = h.sk_assignment_leadership_order_5
LEFT JOIN
  datalake_hr_system.employee_ids AS wi6
    ON wi6.id_period_of_service = h.sk_assignment_leadership_order_6
LEFT JOIN
  datalake_hr_system.employee_ids AS wi7
    ON wi7.id_period_of_service = h.sk_assignment_leadership_order_7
LEFT JOIN
  datalake_hr_system.employee_ids AS wi8
    ON wi8.id_period_of_service = h.sk_assignment_leadership_order_8
LEFT JOIN
  datalake_hr_system.employee_ids AS wi9
    ON wi9.id_period_of_service = h.sk_assignment_leadership_order_9