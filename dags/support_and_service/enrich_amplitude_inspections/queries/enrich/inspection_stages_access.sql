WITH inspections AS (
    SELECT DISTINCT
        id_inspection,
        id_client_side,
        id_contract,
        type AS inspection_type,
        ts_created,
        ts_updated,
        year,
        month,
        day
    FROM
        datalake_inspections_clean.inspection_aud AS ia
    WHERE
        DATE(ia.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    QUALIFY
        ia.ts_updated = MAX(ia.ts_updated) OVER(PARTITION BY ia.id_inspection)
),
review_events AS (
    SELECT
        ia.id_inspection,
        ia.id_client_side,
        ia.id_contract,
        ia.inspection_type,
        COALESCE(SUM(CAST(insp.user_type = 'Proprietario' AS SMALLINT)), 0) AS total_owner_access_review,
        COALESCE(MAX(insp.user_type = 'Proprietario'), FALSE) AS has_owner_access_review,
        COALESCE(SUM(CAST(insp.user_type = 'Inquilino' AS SMALLINT)), 0) AS total_tenant_access_review,
        COALESCE(MAX(insp.user_type = 'Inquilino'), FALSE) AS has_tenant_access_review,
        MIN(
            CASE
            WHEN insp.user_type = 'Proprietario' THEN insp.ts_event
            END
        ) AS ts_first_owner_access_review,
        MAX(
            CASE
                WHEN insp.user_type = 'Proprietario' THEN insp.ts_event
            END
        ) AS ts_last_owner_access_review,
        MIN(
            CASE
            WHEN insp.user_type = 'Inquilino' THEN insp.ts_event
            END
        ) AS ts_first_tenant_access_review,
        MAX(
            CASE
                WHEN insp.user_type = 'Inquilino' THEN insp.ts_event
            END
        ) AS ts_last_tenant_access_review,
        ia.ts_created AS ts_inspection_created,
        ia.ts_updated AS ts_inspection_updated,
        ia.year,
        ia.month,
        ia.day
    FROM
        inspections AS ia
    LEFT JOIN
        datalake_amplitude_inspections.inspection_review_page_viewed_events AS insp
            ON insp.id_client_side = ia.id_client_side
    GROUP BY
        ALL
),
budget_approval_events AS (
    SELECT
        ia.id_inspection,
        ia.id_client_side,
        ia.id_contract,
        ia.inspection_type,
        COALESCE(SUM(CAST(ba.user_type in ('Proprietario','OWNER') AS SMALLINT)), 0) AS total_owner_access_budget_approval,
        COALESCE(MAX(ba.user_type  IN ('Proprietario','OWNER')), FALSE) AS has_owner_access_budget_approval,
        COALESCE(SUM(CAST(ba.user_type IN ('RESIDENT','TENANT','Morador','Inquilino') AS SMALLINT)), 0) AS total_tenant_access_budget_approval,
        COALESCE(MAX(ba.user_type IN('RESIDENT','TENANT','Morador','Inquilino')), FALSE) AS has_tenant_access_budget_approval,
        MIN(
            CASE
            WHEN ba.user_type in ('Proprietario','OWNER') THEN ba.ts_event
            END
        ) AS ts_first_owner_access_budget_approval,
        MAX(
            CASE
                WHEN ba.user_type in ('Proprietario','OWNER') THEN ba.ts_event
            END
        ) AS ts_last_owner_access_budget_approval,
        MIN(
            CASE
            WHEN ba.user_type IN ('RESIDENT','TENANT','Morador','Inquilino') THEN ba.ts_event
            END
        ) AS ts_first_tenant_access_budget_approval,
        MAX(
            CASE
                WHEN ba.user_type IN ('RESIDENT','TENANT','Morador','Inquilino') THEN ba.ts_event
            END
        ) AS ts_last_tenant_access_budget_approval,
        ia.ts_created AS ts_inspection_created,
        ia.ts_updated AS ts_inspection_updated,
        ia.year,
        ia.month,
        ia.day
    FROM
        inspections AS ia
    LEFT JOIN
        datalake_amplitude_clean.170698_inspection_budgetapproval_home_page_viewed_events AS ba
            ON ba.id_client_side = ia.id_client_side
    GROUP BY
        ALL
)
SELECT
    re.id_inspection,
    re.id_client_side,
    re.id_contract,
    re.inspection_type,
    re.total_owner_access_review,
    re.has_owner_access_review,
    re.total_tenant_access_review,
    re.has_tenant_access_review,
    ba.total_owner_access_budget_approval,
    ba.has_owner_access_budget_approval,
    ba.total_tenant_access_budget_approval,
    ba.has_tenant_access_budget_approval,
    re.ts_first_owner_access_review,
    re.ts_last_owner_access_review,
    re.ts_first_tenant_access_review,
    re.ts_last_tenant_access_review,
    ba.ts_first_owner_access_budget_approval,
    ba.ts_last_owner_access_budget_approval,
    ba.ts_first_tenant_access_budget_approval,
    ba.ts_last_tenant_access_budget_approval,
    re.ts_inspection_created,
    re.ts_inspection_updated,
    re.year,
    re.month,
    re.day
FROM
    review_events AS re
JOIN
    budget_approval_events AS ba
        ON re.id_inspection = ba.id_inspection
