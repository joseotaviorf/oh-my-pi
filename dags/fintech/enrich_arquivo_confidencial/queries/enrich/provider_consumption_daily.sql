WITH requests_with_integration AS (
    SELECT
        rt.id AS request_id,
        rt.id_integration_report,
        rt.business_unit,
        rt.is_cached,
        rt.success,
        rt.ts_created,
        DATE(rt.ts_created) AS dt_requested,
        TRIM(UPPER(ir.integration_provider)) AS integration_provider
    FROM
        datalake_arquivo_confidencial_clean.request_tracker AS rt
    LEFT JOIN
        datalake_arquivo_confidencial_clean.integration_report AS ir
        ON rt.id_integration_report = ir.id
),

requests_with_pricing AS (
    SELECT
        r.request_id,
        r.dt_requested,
        r.business_unit,
        r.is_cached,
        r.success,
        r.integration_provider,
        p.external_product_code,
        p.product_name,
        p.provider,
        p.unit_price,
        p.included_monthly,
        p.included_annual,
        p.exceed_unit_price,
        p.weight,
        p.valid_from,
        p.valid_to,
        CASE
            WHEN p.included_annual IS NOT NULL
                OR p.included_monthly IS NOT NULL
            THEN 'FRANCHISE'
            ELSE 'UNIT_PRICE'
        END AS pricing_type,
        CASE
            WHEN p.included_annual IS NOT NULL
                OR p.included_monthly IS NOT NULL
            THEN p.exceed_unit_price
            ELSE p.unit_price
        END AS request_cost,
        CASE
            WHEN r.dt_requested >= p.valid_from
                AND (p.valid_to IS NULL OR r.dt_requested <= p.valid_to)
            THEN TRUE
            ELSE FALSE
        END AS is_within_contract
    FROM
        requests_with_integration AS r
    LEFT JOIN
        datalake_gsheets_clean.provider_pricing AS p
        ON p.provider_code = r.integration_provider
),

daily_aggregation AS (
    SELECT
        dt_requested,
        business_unit,
        integration_provider,
        is_cached,
        success,
        external_product_code,
        product_name,
        provider,
        unit_price,
        included_monthly,
        included_annual,
        exceed_unit_price,
        pricing_type,
        weight,
        valid_from,
        valid_to,
        request_cost,
        is_within_contract,
        COUNT(DISTINCT request_id) AS daily_requests
    FROM
        requests_with_pricing
    GROUP BY
        dt_requested,
        business_unit,
        integration_provider,
        is_cached,
        success,
        external_product_code,
        product_name,
        provider,
        unit_price,
        included_monthly,
        included_annual,
        exceed_unit_price,
        pricing_type,
        weight,
        valid_from,
        valid_to,
        request_cost,
        is_within_contract
)

SELECT
    dt_requested,
    business_unit,
    integration_provider,
    is_cached,
    success,
    external_product_code,
    product_name,
    provider,
    unit_price,
    included_monthly,
    included_annual,
    exceed_unit_price,
    pricing_type,
    weight,
    valid_from,
    valid_to,
    is_within_contract,
    daily_requests,
    CASE
        WHEN is_cached = FALSE
            AND is_within_contract = TRUE
        THEN request_cost * daily_requests
        ELSE 0
    END AS daily_cost,
    CASE
        WHEN is_cached = TRUE
            AND is_within_contract = TRUE
        THEN request_cost * daily_requests
        ELSE 0
    END AS daily_saving
FROM
    daily_aggregation
