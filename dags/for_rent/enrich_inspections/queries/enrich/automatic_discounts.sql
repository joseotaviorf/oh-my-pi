-- BLOCK 1: LEGACY (Historical data until 2025-12-04)
-- Source: Only automatic_invoice (as it was before)
-- BLOCK 2: NEW FLOW (From 2025-12-05 onwards)
-- Source: invoice_discount + automatic_invoice
WITH united_data AS (
    SELECT
        id_contract,
        uuid_inspection,
        CAST(ts_created AS DATE) AS dt_discount_creation,
        NULL AS dt_discount_response,
        CAST(ts_created AS DATE) AS dt_invoice_creation,
        TRUE AS has_discount_try,
        NULL AS is_discount_accepted,
        TRUE AS has_applied_discount,
        'AUTOMATIC_BANDAID' AS model_discount_type,
        CASE
            WHEN tenant_cost = 0 THEN 'total'
            WHEN tenant_cost > 0 THEN 'partial'
            ELSE 'error'
        END AS discount_value_type,
        NULL AS discount_stage,
        NULL AS id_checkpoint,
        NULL AS inspection_cost,
        NULL AS disputed_inspection_cost,
        ROUND((owner_cost - tenant_cost), 2) AS discount_value,
        NULL AS discount_reviewed_value,
        (owner_cost - tenant_cost) AS invoice_discount_value,
        tenant_cost AS invoice_tenant_cost,
        owner_cost AS invoice_owner_cost,
        NULL AS has_tenant_approval,
        NULL AS has_landlord_approval,
        NULL AS has_landlord_repair_request,
        NULL AS discount_is_eviction,
        NULL AS discount_is_spoc,
        NULL AS person_blocked,
        'automatic_invoice' AS db_source,
        ROW_NUMBER() OVER(PARTITION BY id_contract ORDER BY ts_created DESC) AS rn
    FROM
        datalake_inspection_services_clean.automatic_invoice
    WHERE 
        tag = 'AUTOMATIC_BANDAID'
        AND CAST(ts_created AS DATE) < DATE('2025-12-05')
        AND CAST(ts_created AS DATE) >= DATE('2025-01-01')

    UNION ALL

    SELECT
        disc.id_contract,
        disc.uuid_inspection,
        CAST(disc.ts_created AS DATE) AS dt_discount_creation,
        CAST(disc.dt_discount_accepted AS DATE) AS dt_discount_response,
        CAST(inv.ts_created AS DATE) AS dt_invoice_creation,
        CASE
            WHEN inv.ts_created IS NOT NULL THEN TRUE
            WHEN disc.discount_type = 'OFFERED_DISCOUNT'
                AND disc.discount_reviewed_value > 0 THEN TRUE
            ELSE FALSE
        END AS has_discount_try,
        disc.is_discount_accepted,
        CASE
            WHEN inv.ts_created IS NOT NULL THEN TRUE
            ELSE FALSE
        END AS has_applied_discount,
        disc.discount_type AS model_discount_type,
        disc.discount_value_type,
        CASE
            WHEN disc.id_checkpoint = 'REVIEW_COMPULSORY' THEN '1st review - Compulsory'
            WHEN disc.id_checkpoint = 'REVIEW' THEN '1st review - Disagreement'
            WHEN disc.id_checkpoint IN ('BUDGET_REVIEW', 'BUDGET_REVIEW_SINGLE_CLEAR_JOURNEY', 'TENANT_AC_REVIEW') THEN '2nd review - Disagreement'
            WHEN disc.id_checkpoint = 'BUDGET_REVIEW_COMPULSORY' THEN '2nd review - Compulsory'
            ELSE 'error'
        END AS discount_stage,
        disc.id_checkpoint,
        disc.inspection_cost,
        disc.disputed_inspection_cost,
        ROUND(disc.discount_value, 2) AS discount_value,
        disc.discount_reviewed_value,
        (inv.owner_cost - inv.tenant_cost) AS invoice_discount_value,
        inv.tenant_cost AS invoice_tenant_cost,
        inv.owner_cost AS invoice_owner_cost,
        disc.has_tenant_approval,
        disc.has_landlord_approval,
        disc.has_landlord_repair_request,
        disc.is_eviction AS discount_is_eviction,
        disc.is_spoc AS discount_is_spoc,
        disc.person_blocked,
        'invoice_discount_and_automatic_invoice' AS db_source,
        ROW_NUMBER() OVER(PARTITION BY disc.id_contract ORDER BY disc.ts_created DESC) AS rn
    FROM
        datalake_inspection_services_clean.invoice_discount AS disc
    LEFT JOIN
        datalake_inspection_services_clean.automatic_invoice AS inv
            ON disc.id_contract = inv.id_contract
            AND inv.tag IN ('AUTOMATIC_BANDAID', 'OFFERED_DISCOUNT')
    WHERE
        CAST(disc.ts_created AS DATE) >= DATE('2025-12-05')
)
SELECT
    id_contract,
    uuid_inspection,
    id_checkpoint,
    model_discount_type,
    discount_value_type,
    discount_stage,
    CAST(inspection_cost AS DOUBLE) AS inspection_cost,
    CAST(disputed_inspection_cost AS DOUBLE) AS disputed_inspection_cost,
    CAST(discount_value AS DOUBLE) AS discount_value,
    CAST(discount_reviewed_value AS DOUBLE) AS discount_reviewed_value,
    CAST(invoice_discount_value AS DOUBLE) AS invoice_discount_value,
    CAST(invoice_tenant_cost AS DOUBLE) AS invoice_tenant_cost,
    CAST(invoice_owner_cost AS DOUBLE) AS invoice_owner_cost,
    has_discount_try,
    is_discount_accepted,
    has_applied_discount,
    has_tenant_approval,
    has_landlord_approval,
    has_landlord_repair_request,
    discount_is_eviction,
    discount_is_spoc,
    person_blocked,
    db_source,
    dt_discount_creation,
    dt_discount_response,
    dt_invoice_creation
FROM
    united_data
WHERE
    rn = 1