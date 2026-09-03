-- Notebook allocation roster: which QuintoAndar machine is linked to each employee, current and historical.
-- Exception: reads datalake_plugify_clean.device_inventory because dw_equipment.dim_equipment strips
-- tax_id (CPF) at the DW layer. CPF is the only deterministic key to a person: without it the match
-- rate drops from 94.5% to 93.1% and 55 allocated machines resolve to the wrong employee.
WITH
    reference_snapshot AS (
        SELECT
            MAX(MAKE_DATE(year, month, day)) AS dt_reference
        FROM
            datalake_plugify_clean.device_inventory
        WHERE
            MAKE_DATE(year, month, day) <= DATE('{load_start_date}')
    ),
    device_daily AS (
        SELECT
            MAKE_DATE(inv.year, inv.month, inv.day) AS dt_snapshot,
            UPPER(REGEXP_REPLACE(inv.hostname, '[^A-Za-z0-9._-]', '')) AS hostname,
            NULLIF(REGEXP_REPLACE(COALESCE(inv.tax_id, ''), '[^0-9]', ''), '') AS tax_id_digits,
            NULLIF(LOWER(TRIM(COALESCE(inv.employee_email, ''))), '') AS plugify_email,
            NULLIF(LOWER(TRIM(COALESCE(inv.employee_corporate_email, ''))), '') AS plugify_corporate_email,
            CASE
                WHEN TRIM(COALESCE(inv.employee_name, '')) IN ('', 'Não Atribuído') THEN NULL
                ELSE TRANSLATE(
                    UPPER(REGEXP_REPLACE(TRIM(inv.employee_name), '\\s+', ' ')),
                    'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ',
                    'AAAAAEEEEIIIIOOOOOUUUUCN'
                )
            END AS plugify_employee_name,
            STRUCT(
                inv.serial AS id_serial,
                CASE
                    WHEN UPPER(inv.model) LIKE '%MACBOOK%'
                        OR UPPER(inv.model) LIKE '%IMAC%' THEN 'Apple'
                    WHEN UPPER(inv.model) LIKE '%LATITUDE%'
                        OR UPPER(inv.model) LIKE '%VOSTRO%'
                        OR UPPER(inv.model) LIKE '%PRECISION%'
                        OR UPPER(inv.model) LIKE '%OPTIPLEX%'
                        OR UPPER(inv.model) LIKE '%DELL%' THEN 'Dell'
                    WHEN UPPER(inv.model) LIKE '%THINKPAD%'
                        OR UPPER(inv.model) LIKE '%LENOVO%' THEN 'Lenovo'
                    WHEN UPPER(inv.model) LIKE '%ELITEBOOK%'
                        OR UPPER(inv.model) LIKE '%PROBOOK%' THEN 'HP'
                END AS brand,
                TRIM(SPLIT(REPLACE(inv.model, CHR(39), ''), ',')[0]) AS model_family,
                REPLACE(inv.model, CHR(39), '') AS model,
                inv.sku,
                inv.processor,
                inv.memory_gb,
                inv.operating_system,
                inv.operating_system_version,
                inv.device_owner,
                inv.tracked_by,
                inv.location,
                inv.stock_subheading,
                inv.document_country,
                inv.contract_number,
                inv.term_contract_months,
                inv.rent_price,
                inv.dt_contract_signed,
                inv.dt_contract_started,
                inv.dt_contract_ended,
                inv.dt_term_started,
                inv.dt_term_ended,
                inv.dt_last_contacted,
                inv.dt_last_updated,
                NULLIF(TRIM(COALESCE(inv.employee_cost_center_code, '')), '') AS cost_center_code_plugify
            ) AS device,
            ROW_NUMBER() OVER (
                PARTITION BY
                    MAKE_DATE(inv.year, inv.month, inv.day),
                    UPPER(REGEXP_REPLACE(inv.hostname, '[^A-Za-z0-9._-]', ''))
                ORDER BY
                    inv.ts_load DESC,
                    inv.serial
            ) AS rn_hostname_day
        FROM
            datalake_plugify_clean.device_inventory AS inv
        WHERE
            MAKE_DATE(inv.year, inv.month, inv.day) <= DATE('{load_start_date}')
            AND inv.hostname IS NOT NULL
            AND TRIM(inv.hostname) <> ''
    ),
    key_tax_id AS (
        SELECT
            REGEXP_REPLACE(doc.cpf, '[^0-9]', '') AS key_value,
            MIN(doc.person_number) AS person_number
        FROM
            dw_employee_details.dim_documentation AS doc
        WHERE
            doc.is_current = TRUE
            AND doc.cpf IS NOT NULL
            AND TRIM(doc.cpf) <> ''
        GROUP BY
            REGEXP_REPLACE(doc.cpf, '[^0-9]', '')
    ),
    key_work_email AS (
        SELECT
            LOWER(TRIM(empl.work_email)) AS key_value,
            MIN(empl.person_number) AS person_number
        FROM
            dw_employee_details.dim_employee AS empl
        WHERE
            empl.work_email IS NOT NULL
            AND TRIM(empl.work_email) <> ''
        GROUP BY
            LOWER(TRIM(empl.work_email))
    ),
    key_personal_email AS (
        SELECT
            LOWER(TRIM(cont.personal_email)) AS key_value,
            MIN(cont.person_number) AS person_number
        FROM
            dw_employee_details.dim_contact AS cont
        WHERE
            cont.is_current = TRUE
            AND cont.personal_email IS NOT NULL
            AND TRIM(cont.personal_email) <> ''
        GROUP BY
            LOWER(TRIM(cont.personal_email))
    ),
    key_employee_name AS (
        SELECT
            TRANSLATE(
                UPPER(REGEXP_REPLACE(TRIM(empl.name), '\\s+', ' ')),
                'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ',
                'AAAAAEEEEIIIIOOOOOUUUUCN'
            ) AS key_value,
            MIN(empl.person_number) AS person_number
        FROM
            dw_employee_details.dim_employee AS empl
        WHERE
            empl.name IS NOT NULL
            AND TRIM(empl.name) <> ''
        GROUP BY
            TRANSLATE(
                UPPER(REGEXP_REPLACE(TRIM(empl.name), '\\s+', ' ')),
                'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ',
                'AAAAAEEEEIIIIOOOOOUUUUCN'
            )
        HAVING
            COUNT(DISTINCT empl.person_number) = 1
    ),
    resolved_daily AS (
        SELECT
            dev.dt_snapshot,
            dev.hostname,
            dev.device,
            COALESCE(
                ktax.person_number,
                kwork.person_number,
                kpers.person_number,
                kcorp.person_number,
                kname.person_number
            ) AS person_number,
            CASE
                WHEN ktax.person_number IS NOT NULL THEN 'tax_id'
                WHEN kwork.person_number IS NOT NULL THEN 'work_email'
                WHEN kpers.person_number IS NOT NULL THEN 'personal_email'
                WHEN kcorp.person_number IS NOT NULL THEN 'corporate_email_field'
                WHEN kname.person_number IS NOT NULL THEN 'employee_name'
            END AS matched_by
        FROM
            device_daily AS dev
        LEFT JOIN
            key_tax_id AS ktax
                ON dev.tax_id_digits = ktax.key_value
        LEFT JOIN
            key_work_email AS kwork
                ON dev.plugify_email = kwork.key_value
        LEFT JOIN
            key_personal_email AS kpers
                ON dev.plugify_email = kpers.key_value
        LEFT JOIN
            key_work_email AS kcorp
                ON dev.plugify_corporate_email = kcorp.key_value
        LEFT JOIN
            key_employee_name AS kname
                ON dev.plugify_employee_name = kname.key_value
        WHERE
            dev.rn_hostname_day = 1
    ),
    flagged_change AS (
        SELECT
            res.dt_snapshot,
            res.hostname,
            res.device,
            res.person_number,
            res.matched_by,
            CASE
                WHEN LAG(COALESCE(res.person_number, '#unassigned')) OVER (
                        PARTITION BY res.hostname
                        ORDER BY res.dt_snapshot
                     ) = COALESCE(res.person_number, '#unassigned')
                    AND LAG(res.dt_snapshot) OVER (
                        PARTITION BY res.hostname
                        ORDER BY res.dt_snapshot
                    ) = DATE_SUB(res.dt_snapshot, 1)
                THEN 0
                ELSE 1
            END AS is_period_change
        FROM
            resolved_daily AS res
    ),
    grouped_periods AS (
        SELECT
            chg.dt_snapshot,
            chg.hostname,
            chg.device,
            chg.person_number,
            chg.matched_by,
            SUM(chg.is_period_change) OVER (
                PARTITION BY chg.hostname
                ORDER BY chg.dt_snapshot
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS id_period
        FROM
            flagged_change AS chg
    ),
    association_periods AS (
        SELECT
            grp.hostname,
            grp.person_number,
            MIN(grp.dt_snapshot) AS dt_valid_from,
            MAX(grp.dt_snapshot) AS dt_last_seen,
            COUNT(*) AS count_days_observed,
            MAX_BY(grp.matched_by, grp.dt_snapshot) AS matched_by,
            MAX_BY(grp.device, grp.dt_snapshot) AS device
        FROM
            grouped_periods AS grp
        WHERE
            grp.person_number IS NOT NULL
        GROUP BY
            grp.hostname,
            grp.person_number,
            grp.id_period
    ),
    current_employee AS (
        SELECT
            emp.person_number,
            emp.assignment_number,
            emp.name AS employee_name,
            emp.work_email AS email,
            emp.status AS employment_status,
            emp.employee_tenure_range,
            emp.dt_employee_hired,
            emp.dt_terminated,
            emp.manager_assignment_number,
            emp.manager_name,
            emp.manager_work_email AS manager_email,
            emp.assignment_number_l1,
            emp.name_l1,
            emp.email_l1,
            emp.hierarchy_depth
        FROM
            metric_people.employee_snapshots AS emp
        WHERE
            emp.is_current_for_employee = TRUE
    ),
    management_hierarchy AS (
        SELECT
            hier.assignment_number,
            hier.hierarchy_level
        FROM
            dw_employee_details.dim_management_hierarchy AS hier
        WHERE
            hier.is_current = TRUE
    )
SELECT
    assoc.person_number,
    emp.assignment_number,
    emp.employee_name,
    emp.email,
    emp.employment_status,
    emp.employee_tenure_range,
    emp.dt_employee_hired,
    emp.dt_terminated,
    hier.hierarchy_level,
    emp.hierarchy_depth,
    emp.manager_assignment_number,
    emp.manager_name,
    emp.manager_email,
    emp.assignment_number_l1,
    emp.name_l1,
    emp.email_l1,
    assoc.hostname,
    assoc.device.id_serial AS id_serial,
    assoc.device.brand AS brand,
    assoc.device.model_family AS model_family,
    assoc.device.model AS model,
    assoc.device.sku AS sku,
    assoc.device.processor AS processor,
    assoc.device.memory_gb AS memory_gb,
    assoc.device.operating_system AS operating_system,
    assoc.device.operating_system_version AS operating_system_version,
    assoc.device.device_owner AS device_owner,
    assoc.device.tracked_by AS tracked_by,
    assoc.device.location AS location,
    assoc.device.stock_subheading AS stock_subheading,
    assoc.device.document_country AS document_country,
    assoc.device.contract_number AS contract_number,
    assoc.device.term_contract_months AS term_contract_months,
    assoc.device.rent_price AS rent_price,
    assoc.device.dt_contract_signed AS dt_contract_signed,
    assoc.device.dt_contract_started AS dt_contract_started,
    assoc.device.dt_contract_ended AS dt_contract_ended,
    assoc.device.dt_term_started AS dt_term_started,
    assoc.device.dt_term_ended AS dt_term_ended,
    assoc.device.dt_last_contacted AS dt_last_contacted,
    assoc.device.dt_last_updated AS dt_last_updated,
    assoc.device.cost_center_code_plugify AS cost_center_code_plugify,
    assoc.matched_by,
    assoc.count_days_observed,
    assoc.dt_valid_from,
    CASE
        WHEN assoc.dt_last_seen = ref.dt_reference THEN DATE('9999-12-31')
        ELSE assoc.dt_last_seen
    END AS dt_valid_to,
    assoc.dt_last_seen = ref.dt_reference AS is_current,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    association_periods AS assoc
CROSS JOIN
    reference_snapshot AS ref
LEFT JOIN
    current_employee AS emp
        ON assoc.person_number = emp.person_number
LEFT JOIN
    management_hierarchy AS hier
        ON emp.assignment_number = hier.assignment_number
