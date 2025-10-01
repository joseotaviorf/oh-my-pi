SELECT
    id,
    business_entity_id AS id_business_entity,
    finance_entity_id AS id_finance_entity,
    feature_id AS id_feature,
    get_json_object(request, '$.finance-entity-id') AS id_finance_entity,
    get_json_object(request, '$.business-entity-id') AS id_business_entity,
    get_json_object(request, '$.external-payment-id') AS id_external_payment,
    transaction_name,
    status AS sap_status,
    request,
    from_json(
      get_json_object(request, '$.entries'),
      'array<struct<
        amount: double,
        payment: struct<
          flag: string,
          method: string,
          installments: int
        >,
        `transaction-type`: string,
        `finance-entity-entry-id`: string
      >>'
    ) AS payment_entries,
    get_json_object(request, '$.description') AS description,
    get_json_object(request, '$.source-client') AS source_client,
    get_json_object(request, '$.reference-city') AS reference_city,
    get_json_object(request, '$.reference-state') AS reference_state,
    get_json_object(request, '$.unique-identifier') AS unique_identifier,
    get_json_object(request, '$.finance-entity-type') AS finance_entity_type,
    get_json_object(request, '$.reference-year-month') AS reference_year_month,
    response,
    trigger,
    CAST(get_json_object(request, '$.due-date') AS DATE) AS dt_due_date,
    CAST(get_json_object(request, '$.event-date') AS DATE) AS dt_event_date,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rental_guarantee_raw.sap
