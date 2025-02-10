WITH raw_predicted_durations AS (
    SELECT
        CAST(input_data.id_rent_flow AS BIGINT) AS id_rent_flow,
        CAST(input_data.id_house AS BIGINT) AS id_house,
        CAST(input_data.id_tenant_prospect AS BIGINT) AS id_tenant_prospect,
        BIGINT(DOUBLE(input_data.id_event)) AS id_event,
        input_data.event_type AS event_type,
        MAX_BY(
            output_data.prediction / 30,  -- Convert from days to months
            struct(model_version, ts_inference)
        ) AS predicted_duration,
        MAX_BY(
            CAST(input_data.rent AS DOUBLE),
            struct(model_version, ts_inference)
        ) AS rent,
        MAX_BY(
            from_unixtime(input_data.ts_event / 1000)::TIMESTAMP,
            struct(model_version, ts_inference)
        ) AS ts_event,
        CAST(MAX_BY(
            ts_inference,
            struct(model_version, ts_inference)
        ) AS DATE) AS dt_inference
    FROM (
        SELECT
            ts_inference,
            model_version,
            from_json(input_data, 'MAP<STRING, STRING>') AS input_data,
            from_json(output_data, 'STRUCT<prediction: DOUBLE>') AS output_data
        FROM
            datalake_batch_inference_clean.batch_inference
        WHERE
            model_name = '4rent-eCM-duration_model'
            AND format_string("%04d-%02d-%02d", year, month, day) BETWEEN '{start_date}' AND '{end_date}'
    )
    GROUP BY ALL
),

raw_predicted_conversions AS (
    SELECT
        CAST(input_data.id_rent_flow AS BIGINT) AS id_rent_flow,
        CAST(input_data.id_house AS BIGINT) AS id_house,
        CAST(input_data.id_tenant_prospect AS BIGINT) AS id_tenant_prospect,
        BIGINT(DOUBLE(input_data.id_event)) AS id_event,
        MAX_BY(
            prediction,
            struct(model_version, ts_inference)
        ) AS predicted_conversion
    FROM (
        SELECT
            ts_inference,
            model_version,
            from_json(input_data, 'MAP<STRING, STRING>') AS input_data,
            from_json(output_data, 'STRUCT<prediction: DOUBLE>').prediction AS prediction
        FROM
            datalake_batch_inference_clean.batch_inference
        WHERE
            model_name = '4rent-eCM-conversion_model'
            AND format_string("%04d-%02d-%02d", year, month, day) BETWEEN '{start_date}' AND '{end_date}'
    )
    GROUP BY ALL
),

raw_predictions_table AS (
    SELECT
        id_rent_flow,
        id_house,
        id_tenant_prospect,
        id_event,
        event_type,
        predicted_duration,
        predicted_conversion,
        table1.rent,
        table1.dt_inference,
        table1.ts_event
    FROM
        raw_predicted_durations table1
    JOIN
        raw_predicted_conversions USING (
            id_rent_flow,
            id_house,
            id_tenant_prospect,
            id_event
        )
),

exploded_table AS (
    SELECT
        *,
        CASE
            WHEN months_since_contract_start < predicted_duration
                THEN 1.0
            ELSE predicted_duration - floor(predicted_duration)
        END AS monthly_revenue_multiplier,
        predicted_conversion
    FROM (
        SELECT
            id_rent_flow,
            id_house,
            id_tenant_prospect,
            id_event,
            event_type,
            explode(
                SEQUENCE(1, CAST(CEIL(predicted_duration) AS INT))
            ) AS months_since_contract_start,
            predicted_duration,
            predicted_conversion,
            rent,
            dt_inference,
            ts_event
        FROM
            raw_predictions_table
    )
),

contract_onboarding_costs AS (
    SELECT
        id_rent_flow,
        id_house,
        id_tenant_prospect,
        id_event,
        months_since_contract_start,
        800 AS pre_rental_costs,
        255 AS onboarding_costs
    FROM
        exploded_table
    WHERE
        months_since_contract_start = 1
),

contract_ongoing_costs AS (
    SELECT
        id_rent_flow,
        id_house,
        id_tenant_prospect,
        id_event,
        months_since_contract_start,
        25 AS ongoing_costs
    FROM
        exploded_table
    WHERE
        months_since_contract_start > 1
        AND NOT (months_since_contract_start >= predicted_duration)
),

contract_offboarding_costs AS (
    SELECT
        id_rent_flow,
        id_house,
        id_tenant_prospect,
        id_event,
        months_since_contract_start,
        700 AS offboarding_costs
    FROM
        exploded_table
    WHERE
        months_since_contract_start >= predicted_duration
), 

final_table AS (
    SELECT
        id_rent_flow AS id_flow,
        id_house,
        id_tenant_prospect AS id_prospect,
        id_event,
        event_type,
        ts_event,
        months_since_contract_start,
        predicted_duration as estimated_contract_duration,
        predicted_conversion as estimated_conversion,
        CASE
            WHEN months_since_contract_start = 1 THEN rent  -- Brokerage fee
            ELSE 0.1 * rent * monthly_revenue_multiplier  -- Management Fee + Service Fee
        END * predicted_conversion AS estimated_gross_revenue,
        (
            CASE
                WHEN months_since_contract_start = 1 THEN rent * (1 - 0.35)
                ELSE 0.1 * rent * monthly_revenue_multiplier
            END * (1 - 0.08)
        ) * predicted_conversion AS estimated_net_revenue,
        (
            CASE
                WHEN months_since_contract_start = 1 THEN rent * (1 - 0.35)
                ELSE 0.1 * rent * monthly_revenue_multiplier
            END * (1 - 0.08)
        ) * predicted_conversion AS estimated_net_revenue_after_losses,
        (
            CASE
                WHEN months_since_contract_start = 1 THEN rent * (1 - 0.35)
                ELSE 0.1 * rent * monthly_revenue_multiplier
            END * (1 - 0.08)
            - COALESCE(pre_rental_costs, 0.0)
            - COALESCE(onboarding_costs, 0.0)
            - COALESCE(ongoing_costs, 0.0)
            - COALESCE(offboarding_costs, 0.0)
        ) * predicted_conversion AS estimated_contribution_margin,
        dt_inference,
        CAST(ts_event AS DATE) as dt_event_time
    FROM
        exploded_table
    LEFT JOIN
        contract_onboarding_costs USING (
            id_rent_flow,
            id_house,
            id_tenant_prospect,
            id_event,
            months_since_contract_start
        )
    LEFT JOIN
        contract_ongoing_costs USING (
            id_rent_flow,
            id_house,
            id_tenant_prospect,
            id_event,
            months_since_contract_start
        )
    LEFT JOIN
        contract_offboarding_costs USING (
            id_rent_flow,
            id_house,
            id_tenant_prospect,
            id_event,
            months_since_contract_start
        )
)

SELECT
    id_flow,
    id_house,
    id_prospect,
    id_event,
    event_type,
    ts_event,
    FIRST(estimated_contract_duration) AS estimated_contract_duration,
    FIRST(estimated_conversion) AS estimated_conversion,
    SUM(estimated_gross_revenue) AS estimated_gross_revenue,
    SUM(estimated_net_revenue) AS estimated_net_revenue,
    SUM(estimated_net_revenue_after_losses) AS estimated_net_revenue_after_losses,
    SUM(estimated_contribution_margin) AS estimated_contribution_margin,
    dt_inference,
    dt_event_time
FROM
    final_table
GROUP BY ALL
