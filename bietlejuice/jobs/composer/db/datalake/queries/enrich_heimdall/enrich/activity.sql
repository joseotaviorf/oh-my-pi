SELECT
  dl.id,
  CAST(dl.id_external_contract AS BIGINT) AS id_external_contract,
  CAST(dl.id_house AS BIGINT) AS id_house,
  CAST(
    COALESCE(
      GET_JSON_OBJECT(dl.metadata,'$.userId'), 
      GET_JSON_OBJECT(dl.metadata,'$.user_id')
    ) AS BIGINT
  ) AS id_user,
  GET_JSON_OBJECT(dl.metadata,'$.estadoId') AS id_status,
  CAST(GET_JSON_OBJECT(dl.metadata,'$.rent_flow_id') AS BIGINT) AS id_rent_flow,
  dl.class,
  GET_JSON_OBJECT(FROM_JSON(dl.transition_list,'ARRAY<STRING>')[0], '$.from') AS previous_status,
  dl.status,
  dl.type,
  GET_JSON_OBJECT(dl.metadata,'$.name') AS user_name,
  GET_JSON_OBJECT(dl.metadata,'$.condominium_invoice_url') AS condominium_invoice_url,
  GET_JSON_OBJECT(dl.metadata,'$.condominium_receipt_url') AS condominium_receipt_url,
  GET_JSON_OBJECT(dl.metadata,'$.description') AS description,
  GET_JSON_OBJECT(dl.metadata,'$.eventName') AS event_name,
  GET_JSON_OBJECT(dl.metadata,'$.houseAddress') AS house_address,
  FROM_JSON(GET_JSON_OBJECT(dl.metadata,'$.landlordsContactInfo'), 'ARRAY<STRING>') AS landlords_contact_info,
  COALESCE(
    GET_JSON_OBJECT(dl.metadata,'$.email'), 
    REPLACE(REPLACE(GET_JSON_OBJECT(dl.metadata,'$.emails'), '["' ), '"]')
  ) AS user_email,
  FROM_JSON(GET_JSON_OBJECT(dl.metadata,'$.expenses'), 'ARRAY<STRING>') AS expenses,
  FROM_JSON(GET_JSON_OBJECT(dl.metadata,'$.auditableExpenses'), 'ARRAY<STRING>') AS auditable_expenses,
  CAST(GET_JSON_OBJECT(dl.metadata,'$.ticket_number') AS BIGINT) AS ticket_number,
  CAST(GET_JSON_OBJECT(dl.metadata,'$.discount_months') AS BIGINT) AS discount_months,
  CAST(GET_JSON_OBJECT(dl.metadata,'$.discount_percentage') AS DECIMAL(6,6)) AS discount_percentage,
  CAST(GET_JSON_OBJECT(dl.metadata,'$.discount_amount') AS DECIMAL(14,2)) AS discount_amount,
  CAST(GET_JSON_OBJECT(dl.metadata,'$.discounted_rental') AS DECIMAL(14,2)) AS discounted_rental,
  CAST(GET_JSON_OBJECT(dl.metadata,'$.rental_amount') AS DECIMAL(14,2)) AS rental_amount,
  GET_JSON_OBJECT(dl.metadata,'$.discount_end_year_month') AS discount_end_year_month,
  GET_JSON_OBJECT(dl.metadata,'$.discount_start_year_month') AS discount_start_year_month,
  TO_DATE(
    COALESCE(
      GET_JSON_OBJECT(dl.metadata,'$.start_date'),
      GET_JSON_OBJECT(dl.metadata,'$.contractStartDate.$date')
    )
  ) AS dt_contract_started,
  TO_TIMESTAMP(
    COALESCE(
      GET_JSON_OBJECT(dl.metadata,'$.transferredAt.$date'), 
      GET_JSON_OBJECT(dl.metadata,'$.dataMudanca')
    )
  ) AS ts_transferred,
  COALESCE(
    TO_TIMESTAMP(GET_JSON_OBJECT(dl.metadata,'$.request_date'), 'dd/MM/yyyy HH:mm'),
    TO_TIMESTAMP(GET_JSON_OBJECT(dl.metadata,'$.requestedAt.$date')),
    TO_TIMESTAMP(GET_JSON_OBJECT(dl.metadata,'$.requested_date'), 'yyyy-MM-dd')
  ) AS ts_requested,
  TO_TIMESTAMP(
    GET_JSON_OBJECT(FROM_JSON(dl.transition_list,'ARRAY<STRING>')[0], '$.createdAt.$date')
  ) AS ts_transition_created,
  dl.ts_created,
  dl.ts_updated
FROM
  datalake_heimdall_clean.activity AS dl