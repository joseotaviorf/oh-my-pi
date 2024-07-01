WITH raw_predicted_durations_table AS (
    SELECT
        CAST(input_data.id_rent_flow AS BIGINT) AS id_rent_flow,
        CAST(input_data.id_house AS BIGINT) AS id_house,
        CAST(input_data.id_tenant_prospect AS BIGINT) AS id_tenant_prospect,
        BIGINT(DOUBLE(input_data.id_booking)) AS id_booking,
        BIGINT(DOUBLE(input_data.id_offer)) AS id_offer,
        COALESCE(
            BIGINT(DOUBLE(input_data.id_booking)),
            BIGINT(DOUBLE(input_data.id_offer))
        ) AS id_event,
        MAX_BY(
            output_data.estimated_duration / 30,  -- Convert from days to months
            struct(model_version, ts_inference)
        ) AS estimated_duration,
        MAX_BY(
            CAST(input_data.rent AS DOUBLE),
            struct(model_version, ts_inference)
        ) AS rent,
        MAX_BY(
            from_unixtime(BIGINT(input_data.event_time) / 1000, "yyyy-MM-dd"),
            struct(model_version, ts_inference)
        ) AS dt_event_time,
        CAST(MAX_BY(
            ts_inference,
            struct(model_version, ts_inference)
        ) AS DATE) AS dt_inference
    FROM (
        SELECT
            ts_inference,
            model_version,
            from_json(input_data, 'MAP<STRING, STRING>') AS input_data,
            from_json(output_data, 'STRUCT<estimated_duration: DOUBLE>') AS output_data
        FROM
            datalake_batch_inference_clean.batch_inference
        WHERE
            model_name = 'eCM-duration'
            AND format_string("%04d-%02d-%02d", year, month, day) BETWEEN '{start_date}' AND '{end_date}'
    )
    GROUP BY ALL
),

raw_predicted_vb2cs_table AS (
    SELECT
        CAST(input_data.id_rent_flow AS BIGINT) AS id_rent_flow,
        CAST(input_data.id_house AS BIGINT) AS id_house,
        CAST(input_data.id_tenant_prospect AS BIGINT) AS id_tenant_prospect,
        BIGINT(DOUBLE(input_data.id_booking)) AS id_booking,
        BIGINT(DOUBLE(input_data.id_offer)) AS id_offer,
        COALESCE(
            BIGINT(DOUBLE(input_data.id_booking)),
            BIGINT(DOUBLE(input_data.id_offer))
        ) AS id_event,
        MAX_BY(
            output_data.estimated_vb2cs,
            struct(model_version, ts_inference)
        ) AS estimated_vb2cs
    FROM (
        SELECT
            ts_inference,
            model_version,
            from_json(input_data, 'MAP<STRING, STRING>') AS input_data,
            from_json(output_data, 'STRUCT<estimated_vb2cs: DOUBLE>') AS output_data
        FROM
            datalake_batch_inference_clean.batch_inference
        WHERE
            model_name = 'eCM-vb2cs'
            AND format_string("%04d-%02d-%02d", year, month, day) BETWEEN '{start_date}' AND '{end_date}'
    )
    GROUP BY ALL
),

raw_predicted_do2cs_table AS (
    SELECT
        CAST(input_data.id_rent_flow AS BIGINT) AS id_rent_flow,
        CAST(input_data.id_house AS BIGINT) AS id_house,
        CAST(input_data.id_tenant_prospect AS BIGINT) AS id_tenant_prospect,
        BIGINT(DOUBLE(input_data.id_booking)) AS id_booking,
        BIGINT(DOUBLE(input_data.id_offer)) AS id_offer,
        COALESCE(
            BIGINT(DOUBLE(input_data.id_booking)),
            BIGINT(DOUBLE(input_data.id_offer))
        ) AS id_event,
        MAX_BY(
            output_data.estimated_do2cs,
            struct(model_version, ts_inference)
        ) AS estimated_do2cs
    FROM (
        SELECT
            ts_inference,
            model_version,
            from_json(input_data, 'MAP<STRING, STRING>') AS input_data,
            from_json(output_data, 'STRUCT<estimated_do2cs: DOUBLE>') AS output_data
        FROM
            datalake_batch_inference_clean.batch_inference
        WHERE
            model_name = 'eCM-do2cs'
            AND format_string("%04d-%02d-%02d", year, month, day) BETWEEN '{start_date}' AND '{end_date}'
    )
    GROUP BY ALL
),

raw_predictions_table AS (
    SELECT
        id_rent_flow,
        id_house,
        id_tenant_prospect,
        table1.id_booking,
        table1.id_offer,
        estimated_duration,
        estimated_vb2cs,
        estimated_do2cs,
        table1.rent,
        table1.dt_inference,
        table1.dt_event_time,
        CASE
            WHEN table1.id_booking IS NULL THEN TRUE
            ELSE FALSE
        END AS is_do
    FROM
        raw_predicted_durations_table table1
    JOIN
        raw_predicted_vb2cs_table USING (id_rent_flow, id_house, id_tenant_prospect, id_event)
    JOIN
        raw_predicted_do2cs_table USING (id_rent_flow, id_house, id_tenant_prospect, id_event)
),

exploded_table AS (
    SELECT
        * EXCEPT (is_do),
        CASE
            WHEN months_since_contract_start < estimated_duration
                THEN 1.0
            ELSE estimated_duration - floor(estimated_duration)
        END AS monthly_revenue_multiplier,
        CASE
            WHEN is_do THEN estimated_do2cs
            ELSE estimated_vb2cs
        END AS estimated_conversion_probability
    FROM (
        SELECT
            id_rent_flow,
            id_house,
            id_tenant_prospect,
            id_booking,
            id_offer,
            explode(
                SEQUENCE(1, CAST(CEIL(estimated_duration) AS INT))
            ) AS months_since_contract_start,
            estimated_duration,
            estimated_vb2cs,
            estimated_do2cs,
            rent,
            dt_inference,
            dt_event_time,
            is_do
        FROM
            raw_predictions_table
    )
),

contract_onboarding_costs AS (
    SELECT
        id_rent_flow,
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
        months_since_contract_start,
        25 AS ongoing_costs
    FROM
        exploded_table
    WHERE
        months_since_contract_start > 1
        AND NOT (months_since_contract_start >= estimated_duration)
),

contract_offboarding_costs AS (
    SELECT
        id_rent_flow,
        months_since_contract_start,
        700 AS offboarding_costs
    FROM
        exploded_table
    WHERE
        months_since_contract_start >= estimated_duration
)

SELECT
    id_rent_flow,
    id_house,
    id_tenant_prospect,
    id_booking,
    id_offer,
    months_since_contract_start,
    CASE
        WHEN months_since_contract_start = 1 THEN rent  -- Brokerage fee
        ELSE 0.1 * rent * monthly_revenue_multiplier  -- Management Fee + Service Fee
    END * estimated_conversion_probability AS estimated_gross_revenue,
    (
        CASE
            WHEN months_since_contract_start = 1 THEN rent * (1 - 0.35)
            ELSE 0.1 * rent * monthly_revenue_multiplier
        END * (1 - 0.08)
    ) * estimated_conversion_probability AS estimated_net_revenue,
    (
        CASE
            WHEN months_since_contract_start = 1 THEN rent * (1 - 0.35)
            ELSE 0.1 * rent * monthly_revenue_multiplier
        END * (1 - 0.08)
    ) * estimated_conversion_probability AS estimated_net_revenue_after_losses,
    (
        CASE
            WHEN months_since_contract_start = 1 THEN rent * (1 - 0.35)
            ELSE 0.1 * rent * monthly_revenue_multiplier
        END * (1 - 0.08)
        - COALESCE(pre_rental_costs, 0.0)
        - COALESCE(onboarding_costs, 0.0)
        - COALESCE(ongoing_costs, 0.0)
        - COALESCE(offboarding_costs, 0.0)
    ) * estimated_conversion_probability AS estimated_contribution_margin,
    dt_inference,
    dt_event_time
FROM
    exploded_table
LEFT JOIN
    contract_onboarding_costs USING (id_rent_flow, months_since_contract_start)
LEFT JOIN
    contract_ongoing_costs USING (id_rent_flow, months_since_contract_start)
LEFT JOIN
    contract_offboarding_costs USING (id_rent_flow, months_since_contract_start)