WITH parsed AS (
    SELECT
        BIGINT(`id`) AS id_revenue_share,
        BIGINT(offer_agent_id) AS id_offer_agent,
        BIGINT(offer_partner_id) AS id_offer_partner,
        output AS json_output,
        from_json(
            output,
            'STRUCT<
                `house-id`: BIGINT,
                `brokerage`: DOUBLE,
                `hub-bonus`: DOUBLE,
                `tier-name`: STRING,
                `tqc-bonus`: DOUBLE,
                `sale-price`: DOUBLE,
                `advance-bonus`: DOUBLE,
                `campaign-bonus`: DOUBLE,
                `offer-category`: STRING,
                `participant-id`: STRING,
                `business-unit-id`: INT,
                `participant-role`: STRING,
                `cancellation-date`: STRING,
                `offer-external-id`: STRING,
                `business-unit-name`: STRING,
                `gross-remuneration`: DOUBLE,
                `remuneration-bonus`: DOUBLE,
                `cancellation-reason`: STRING,
                `offer-signature-date`: STRING,
                `participant-paid-fee`: DOUBLE,
                `payment-allowed-date`: STRING,
                `remuneration-baseline`: DOUBLE,
                `supply-acquisition-share`: DOUBLE,
                `forbrokers-model-partner-brokerage-fee`: DOUBLE,
                `quintoandar-model-partner-brokerage-fee`: DOUBLE
            >'
        ) AS json_parsed,
        errors AS json_errors,
        TIMESTAMP(invalidated_at) AS ts_invalidated,
        TIMESTAMP(created_at) AS ts_created,
        op_cdc,
        ts_cdc_transaction,
        ts_database_transaction
    FROM
        datalake_nazare_raw.revenue_share_by_participant
)
SELECT
    id_revenue_share,
    id_offer_agent,
    id_offer_partner,
    CAST(get_json_object(json_output, '$.house-id') AS BIGINT) AS id_house_json_out,
    CAST(json_parsed.`house-id` AS BIGINT) AS id_house_json_parsed,
    json_output,
    json_parsed,
    json_errors,
    ts_invalidated,
    ts_created,
    op_cdc,
    ts_cdc_transaction,
    ts_database_transaction
FROM
    parsed
