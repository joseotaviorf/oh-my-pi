WITH raw_predicted_conversions AS (
  SELECT
    input_data.id_sale_flow,
    CAST(input_data.id_buyer AS INT) AS id_buyer,
    CAST(input_data.id_house AS INT) AS id_house,
    CAST(input_data.id_event AS INT) AS id_event,
    MAX_BY(CAST(FROM_UNIXTIME(input_data.ts_event / 1000) AS TIMESTAMP), ts_inference) AS ts_event,
    MAX_BY(CAST(input_data.listing_price AS DOUBLE), ts_inference) AS listing_price,
    MAX_BY(prediction, ts_inference) AS predicted_conversion,
    CAST(MAX(ts_inference) AS DATE) AS dt_inference
  FROM (
    SELECT
      ts_inference,
      model_version,
      FROM_JSON(input_data, 'MAP<STRING, STRING>') AS input_data,
      FROM_JSON(output_data, 'STRUCT<prediction: DOUBLE>').prediction AS prediction
    FROM datalake_batch_inference_clean.batch_inference
    WHERE
      model_name = '4sale-eCM-conversion_model'
      AND FORMAT_STRING('%04d-%02d-%02d', year, month, day) BETWEEN '{start_date}' AND '{end_date}'
  )
  GROUP BY
    id_sale_flow,
    id_buyer,
    id_house,
    id_event
), raw_predicted_discounts AS (
  SELECT
    CAST(input_data.id_booking AS INT) AS id_event,
    MAX_BY(prediction, ts_inference) AS predicted_discount
  FROM (
    SELECT
      ts_inference,
      model_version,
      FROM_JSON(input_data, 'MAP<STRING, STRING>') AS input_data,
      FROM_JSON(output_data, 'STRUCT<prediction: DOUBLE>').prediction AS prediction
    FROM datalake_batch_inference_clean.batch_inference
    WHERE
      model_name = '4sale-eCM-discount_model'
      AND FORMAT_STRING('%04d-%02d-%02d', year, month, day) BETWEEN '{start_date}' AND '{end_date}'
  )
  GROUP BY
    id_event
), all_predictions_table AS (
  SELECT
    *
  FROM raw_predicted_conversions
  JOIN raw_predicted_discounts
    USING (id_event)
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
    0.05478285962329783 /* Brokerage Fee */ * predicted_discount * listing_price
  ) AS estimated_gross_revenue,
  predicted_conversion * (
    (
      1 - 0.38716736992579215 /* Revenue Sharing Costs */ - 0.07442162144958478 /* Sales Tax */
    ) * 0.05478285962329783 /* Brokerage Fee */ * predicted_discount * listing_price
  ) AS estimated_net_revenue,
  predicted_conversion * (
    (
      1 - 0.38716736992579215 /* Revenue Sharing Costs */ - 0.07442162144958478 /* Sales Tax */
    ) * 0.05478285962329783 /* Brokerage Fee */ * predicted_discount * listing_price - 11342.35887052643 /* Operational Costs Per CCV */
  ) AS estimated_contribution_margin,
  CAST(ts_event AS DATE) AS dt_event_time,
  dt_inference
FROM all_predictions_table
