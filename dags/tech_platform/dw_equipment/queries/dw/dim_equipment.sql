WITH src_ranked AS (
    SELECT
        src.serial,
        src.sku,
        src.model,
        src.operating_system,
        src.operating_system_version,
        src.processor,
        src.memory_gb,
        src.hostname,
        src.device_owner,
        src.contract_number,
        src.stock_subheading,
        src.location,
        src.tracked_by,
        NULLIF(src.document_country, '') AS document_country,
        NULLIF(src.employee_email, '') AS employee_email,
        NULLIF(NULLIF(src.employee_name, ''), 'Não Atribuído') AS employee_name,
        NULLIF(src.employee_cost_center_code, '') AS employee_cost_center_code,
        NULLIF(src.employee_department, '') AS employee_department,
        NULLIF(src.employee_group, '') AS employee_group,
        src.term_contract_months,
        src.rent_price,
        src.dt_contract_signed,
        src.dt_contract_started,
        src.dt_contract_ended,
        src.dt_term_started,
        src.dt_term_ended,
        src.dt_last_contacted,
        src.dt_last_updated,
        ROW_NUMBER() OVER (
            PARTITION BY
                src.serial
            ORDER BY
                src.ts_load DESC NULLS LAST,
                src.year DESC,
                src.month DESC,
                src.day DESC
        ) AS rn_dedup
    FROM
        datalake_plugify_clean.device_inventory AS src
    WHERE
        src.serial IS NOT NULL
)
SELECT
    MD5(serial) AS sk_equipment,
    serial AS id_serial,
    sku,
    model,
    operating_system,
    operating_system_version,
    processor,
    memory_gb,
    hostname,
    device_owner,
    contract_number,
    stock_subheading,
    location,
    tracked_by,
    document_country,
    employee_email,
    employee_name,
    employee_cost_center_code,
    employee_department,
    employee_group,
    term_contract_months,
    rent_price,
    dt_contract_signed,
    dt_contract_started,
    dt_contract_ended,
    dt_term_started,
    dt_term_ended,
    dt_last_contacted,
    dt_last_updated,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day
FROM
    src_ranked
WHERE
    rn_dedup = 1
