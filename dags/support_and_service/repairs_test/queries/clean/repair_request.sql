SELECT
  id,
  contract_id AS id_contract,
  house_id AS id_house,
  requester_user_id AS id_requester_user,
  third_party_crm_ticket_external_id AS id_third_party_crm_ticket_external,
  customer_user_id AS id_customer_user,
  taskmaster_task_id AS id_taskmaster_task,
  allow_personal_info_sharing,
  status,
  journey,
  third_party_crm,
  origin_channel,
  assumed_urgency,
  owner_approval,
  service_provider,
  zendesk_tickets_info,
  created_at AS ts_created,
  updated_at AS ts_updated,
  year,
  month,
  day
FROM
  datalake_repairs_test_raw.repair_request