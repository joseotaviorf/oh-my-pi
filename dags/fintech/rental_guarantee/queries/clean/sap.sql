WITH entries_parsed AS (
    SELECT
        id,
        business_entity_id,
        finance_entity_id,
        feature_id,
        request,
        transaction_name,
        status,
        response,
        trigger,
        created_at,
        updated_at,
        FROM_JSON(
            GET_JSON_OBJECT(request, '$.entries'),
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
        ) AS entries_raw
    FROM
        datalake_rental_guarantee_raw.sap
)
SELECT
    id,
    business_entity_id AS id_business_entity,
    finance_entity_id AS id_finance_entity,
    feature_id AS id_feature,
    GET_JSON_OBJECT(request, '$.external-payment-id') AS id_external_payment,
    transaction_name,
    status AS sap_status,
    request,
    TRANSFORM(
        entries_raw,
        e -> NAMED_STRUCT(
            'amount', e.amount,
            'payment', e.payment,
            'transaction_type', e.`transaction-type`,
            'finance_entity_entry_id', e.`finance-entity-entry-id`
        )
    ) AS payment_entries,
    GET_JSON_OBJECT(request, '$.description') AS description,
    GET_JSON_OBJECT(request, '$.source-client') AS source_client,
    GET_JSON_OBJECT(request, '$.reference-city') AS reference_city,
    GET_JSON_OBJECT(request, '$.reference-state') AS reference_state,
    GET_JSON_OBJECT(request, '$.unique-identifier') AS unique_identifier,
    GET_JSON_OBJECT(request, '$.finance-entity-type') AS finance_entity_type,
    GET_JSON_OBJECT(request, '$.reference-year-month') AS reference_year_month,
    response,
    trigger,
    COALESCE(
        ELEMENT_AT(
            TRANSFORM(
                FILTER(
                    entries_raw,
                    e -> e.`transaction-type` NOT LIKE '%receita-a-reconhecer%'
                ),
                e -> e.amount
            ),
            1
        ),
        ELEMENT_AT(
            TRANSFORM(
                entries_raw,
                e -> e.amount
            ),
            1
        ),
        CAST(0.0 AS DOUBLE)
    ) AS amount,
    CAST(GET_JSON_OBJECT(request, '$.due-date') AS DATE) AS dt_due_date,
    CAST(GET_JSON_OBJECT(request, '$.event-date') AS DATE) AS dt_event_date,
    created_at AS ts_created,
    updated_at AS ts_updated,
    op_cdc,
    ts_cdc_transaction,
    ts_database_transaction
FROM
    entries_parsed
