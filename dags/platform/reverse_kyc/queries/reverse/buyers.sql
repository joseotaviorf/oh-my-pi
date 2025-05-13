WITH buyer_personal_data AS (
    SELECT DISTINCT
        bd.id_docx_folder,
        GET_JSON_OBJECT(d.attributes, '$.cpf') AS cpf,
        GET_JSON_OBJECT(d.attributes, '$.cnpj') AS cnpj,
        GET_JSON_OBJECT(d.attributes, '$.fullName') AS full_name,
        GET_JSON_OBJECT(d.attributes, '$.corporateReason') AS corporate_reason,
        GET_JSON_OBJECT(d.attributes, '$.email') AS email
    FROM datalake_sales_flow_clean.buyer_data bd
    JOIN datalake_sales_flow_clean.sales_flow sf ON sf.id = bd.id_sales_flow AND sf.is_canceled = FALSE
    JOIN datalake_sales_flow_clean.ccv c ON sf.id = c.id_sales_flow AND c.status = 'SIGNED'
    JOIN datalake_docx_clean.document d ON d.id_folder = bd.id_docx_folder
    JOIN datalake_docx_clean.document_type dt ON dt.id = d.id_document_type AND dt.name = 'PERSONAL_DATA'
    WHERE c.ts_signed >= CURRENT_DATE - INTERVAL '12' MONTH
        AND bd.signer_status = 'SIGNER'
        AND bd.id_docx_folder IS NOT NULL
),
buyer_data AS (
    SELECT
        d.id_folder,
        d.attributes,
        d.id_document_type,
        ROW_NUMBER() OVER (PARTITION BY d.id_folder ORDER BY d.id) AS row_num,
        bpd.cpf,
        bpd.cnpj,
        bpd.full_name,
        bpd.corporate_reason,
        bpd.email
    FROM datalake_docx_clean.document d
    JOIN datalake_docx_clean.document_type dt ON dt.id = d.id_document_type AND dt.name = 'PERSONAL_DATA'
    JOIN buyer_personal_data bpd ON bpd.id_docx_folder = d.id_folder
),
buyer_contract_counts AS (
    SELECT
        bd.cpf,
        bd.cnpj,
        COUNT(DISTINCT bd2.id_sales_flow) AS contract_count
    FROM buyer_data bd
    JOIN datalake_sales_flow_clean.buyer_data bd2 ON 1=1
    JOIN buyer_personal_data bpd ON bpd.id_docx_folder = bd2.id_docx_folder
    JOIN datalake_sales_flow_clean.sales_flow sf2 ON sf2.id = bd2.id_sales_flow AND sf2.is_canceled = FALSE
    JOIN datalake_sales_flow_clean.ccv c2 ON c2.id = sf2.id AND c2.status = 'SIGNED'
    WHERE c2.ts_signed >= CURRENT_DATE - INTERVAL '12' MONTH
        AND bd2.signer_status = 'SIGNER'
        AND (bpd.cpf = bd.cpf OR bpd.cnpj = bd.cnpj)
    GROUP BY bd.cpf, bd.cnpj
),
buyers AS (
    SELECT
        COALESCE(bd.full_name, bd.corporate_reason) AS name_corporate_name,
        COALESCE(bd.cpf, bd.cnpj) AS cpf_cnpj,
        bd.email,
        'N/A' as legal_representative_name,
        'N/A' as legal_representative_cpf,
        'BUYER' AS business_relationship,
        'N/A' AS business_relationship_status,
        CASE
            WHEN cc.contract_count > 1 THEN 'YES'
            ELSE 'NO'
        END AS has_another_contract,
        CASE
            WHEN bd.cpf IS NOT NULL THEN 'PF'
            WHEN bd.cnpj IS NOT NULL THEN 'PJ'
        END AS person_type
    FROM buyer_data bd
    LEFT JOIN buyer_contract_counts cc ON bd.cpf = cc.cpf AND bd.cnpj = cc.cnpj
    WHERE bd.row_num = 1
)
SELECT * FROM buyers