WITH seller_personal_data AS (
    SELECT DISTINCT
        sd.id_docx_folder,
        GET_JSON_OBJECT(d.attributes, '$.cpf') AS cpf,
        GET_JSON_OBJECT(d.attributes, '$.cnpj') AS cnpj
    FROM
        datalake_sales_flow_clean.seller_data sd
    JOIN
        datalake_sales_flow_clean.sales_flow sf ON sf.id = sd.id_sales_flow AND sf.is_canceled = FALSE
    JOIN
        datalake_sales_flow_clean.ccv c ON sf.id = c.id_sales_flow AND c.status = 'SIGNED'
    JOIN
        datalake_docx_clean.document d ON d.id_folder = sd.id_docx_folder
    JOIN
        datalake_docx_clean.document_type dt ON dt.id = d.id_document_type AND dt.name = 'PERSONAL_DATA'
    WHERE
        c.ts_signed >= CURRENT_DATE - INTERVAL '12' MONTH
        AND sd.is_ccv_signer = TRUE
        AND sd.id_docx_folder IS NOT NULL
),
seller_data AS (
    SELECT
        d.id_folder,
        d.attributes,
        d.id_document_type,
        ROW_NUMBER() OVER (PARTITION BY d.id_folder ORDER BY d.id) AS row_num,
        spd.cpf,
        spd.cnpj
    FROM
        datalake_docx_clean.document d
    JOIN
        datalake_docx_clean.document_type dt ON dt.id = d.id_document_type AND dt.name = 'PERSONAL_DATA'
    JOIN seller_personal_data spd ON spd.id_docx_folder = d.id_folder
),
seller_contract_counts AS (
    SELECT
        sd.cpf,
        sd.cnpj,
        COUNT(DISTINCT sd2.id_sales_flow) AS contract_count
    FROM
        seller_data sd
    JOIN
        datalake_sales_flow_clean.seller_data sd2 ON 1=1
    JOIN seller_personal_data spd ON spd.id_docx_folder = sd2.id_docx_folder
    JOIN datalake_sales_flow_clean.sales_flow sf2 ON sf2.id = sd2.id_sales_flow AND sf2.is_canceled = FALSE
    JOIN datalake_sales_flow_clean.ccv c2 ON c2.id = sf2.id AND c2.status = 'SIGNED'
    WHERE c2.ts_signed >= CURRENT_DATE - INTERVAL '12' MONTH
      AND sd2.is_ccv_signer = TRUE
      AND (spd.cpf = sd.cpf OR spd.cnpj = sd.cnpj)
    GROUP BY sd.cpf, sd.cnpj
),
sellers AS (
    SELECT
        COALESCE(
            GET_JSON_OBJECT(sd.attributes, '$.fullName'),
            GET_JSON_OBJECT(sd.attributes, '$.corporateReason')
        ) AS name_corporate_name,
        COALESCE(
            GET_JSON_OBJECT(sd.attributes, '$.cpf'),
            GET_JSON_OBJECT(sd.attributes, '$.cnpj')
        ) AS cpf_cnpj,
        GET_JSON_OBJECT(sd.attributes, '$.email') AS email,
        'N/A' as legal_representative_name,
        'N/A' as legal_representative_cpf,
        'SELLER' AS business_relationship,
        'N/A' AS business_relationship_status,
        CASE
            WHEN cc.contract_count > 1 THEN 'YES'
            ELSE 'NO'
        END AS has_another_contract,
        CASE
            WHEN GET_JSON_OBJECT(sd.attributes, '$.cpf') IS NOT NULL THEN 'PF'
            WHEN GET_JSON_OBJECT(sd.attributes, '$.cnpj') IS NOT NULL THEN 'PJ'
        END AS person_type
    FROM
        seller_data sd
    LEFT JOIN seller_contract_counts cc ON sd.cpf = cc.cpf AND sd.cnpj = cc.cnpj
    WHERE sd.row_num = 1
)
SELECT * FROM sellers