SELECT
    BIGINT(`id`) AS id_revenue_share,
    BIGINT(offer_agent_id) AS id_offer_agent,
    BIGINT(offer_partner_id) AS id_offer_partner,
    output AS json_output,
    to_json(
        from_json(output, 'STRUCT<
        `house-id`: STRING,
        `brokerage`: STRING,
        `hub-bonus`: STRING,
        `tier-name`: STRING,
        `tqc-bonus`: STRING,
        `sale-price`: STRING,
        `advance-bonus`: STRING,
        `campaign-bonus`: STRING,
        `offer-category`: STRING,
        `participant-id`: STRING,
        `business-unit-id`: STRING,
        `participant-role`: STRING,
        `cancellation-date`: STRING,
        `offer-external-id`: STRING,
        `business-unit-name`: STRING,
        `gross-remuneration`: STRING,
        `remuneration-bonus`: STRING,
        `cancellation-reason`: STRING,
        `offer-signature-date`: STRING,
        `participant-paid-fee`: STRING,
        `payment-allowed-date`: STRING,
        `remuneration-baseline`: STRING,
        `supply-acquisition-share`: STRING,
        `forbrokers-model-partner-brokerage-fee`: STRING,
        `quintoandar-model-partner-brokerage-fee`: STRING
    >')
    ) AS json_output_pd,
    errors AS json_errors,
    TIMESTAMP(invalidated_at) AS ts_invalidated,
    TIMESTAMP(created_at) AS ts_created
FROM
    datalake_nazare_raw.revenue_share_by_participant
