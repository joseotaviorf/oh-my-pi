WITH raw_predicted_conversions AS (
    SELECT
        input_data.id_sale_flow,
        input_data.id_buyer::INT AS id_buyer,
        input_data.id_house::INT AS id_house,
        input_data.id_event::INT AS id_event,
        max_by(from_unixtime(input_data.ts_event / 1000)::TIMESTAMP, ts_inference) AS ts_event,
        max_by(input_data.listing_price::DOUBLE, ts_inference) AS listing_price,
        max_by(prediction, ts_inference) AS predicted_conversion,
        CAST(max(ts_inference) AS DATE) AS dt_inference
    FROM (
        SELECT
            ts_inference,
            model_version,
            from_json(input_data, 'MAP<STRING, STRING>') AS input_data,
            from_json(output_data, 'STRUCT<prediction: DOUBLE>').prediction AS prediction
        FROM
            datalake_batch_inference_clean.batch_inference
        WHERE
            model_name = '4sale-eCM-conversion_model'
            AND format_string("%04d-%02d-%02d", year, month, day) BETWEEN '{start_date}' AND '{end_date}'
    )
    GROUP BY
        id_sale_flow,
        id_buyer,
        id_house,
        id_event
), raw_predicted_discounts AS (
    SELECT
        input_data.id_booking::INT AS id_event,
        max_by(prediction, ts_inference) AS predicted_discount
    FROM (
        SELECT
            ts_inference,
            model_version,
            from_json(input_data, 'MAP<STRING, STRING>') AS input_data,
            from_json(output_data, 'STRUCT<prediction: DOUBLE>').prediction AS prediction
        FROM
            datalake_batch_inference_clean.batch_inference
        WHERE
            model_name = '4sale-eCM-discount_model'
            AND format_string("%04d-%02d-%02d", year, month, day) BETWEEN '{start_date}' AND '{end_date}'
    )
    GROUP BY
        id_event
), all_predictions_table AS (
    SELECT
        *
    FROM
        raw_predicted_conversions
    JOIN
        raw_predicted_discounts USING (id_event)
)

SELECT
    id_sale_flow AS id_flow,
    id_buyer AS id_prospect,
    id_house,
    id_event,
    'VB' AS event_type,
    ts_event,
    predicted_conversion AS estimated_conversion,
    predicted_discount AS estimated_discount,
    predicted_conversion * (
        0.05478285962329783  -- Brokerage Fee
        * predicted_discount
        * listing_price
    ) AS estimated_gross_revenue,
    predicted_conversion * (
        (
            1
            - 0.38716736992579215  -- Revenue Sharing Costs
            - 0.07442162144958478  -- Sales Tax
        )
        * 0.05478285962329783  -- Brokerage Fee
        * predicted_discount
        * listing_price
    ) AS estimated_net_revenue,
    predicted_conversion * (
        (
            1
            - 0.38716736992579215  -- Revenue Sharing Costs
            - 0.07442162144958478  -- Sales Tax
        )
        * 0.05478285962329783  -- Brokerage Fee
        * predicted_discount
        * listing_price
        - 11342.35887052643  -- Operational Costs Per CCV
    ) AS estimated_contribution_margin,
    CAST(ts_event AS DATE) AS dt_event_time,
    dt_inference
FROM
    all_predictions_table
