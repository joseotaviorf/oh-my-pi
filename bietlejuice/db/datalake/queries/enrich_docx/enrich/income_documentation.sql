SELECT
    id,
    id_folder,
    id_document_type,
    id_document_context,
    id_context_external,
    CASE
        WHEN id_document_type = 1 THEN 'RG'
        WHEN id_document_type = 2 THEN 'CPF'
        WHEN id_document_type = 3 THEN 'CNH'
        WHEN id_document_type = 4 THEN 'RNE'
        WHEN id_document_type = 7 THEN 'PERSONAL_DATA'
        WHEN id_document_type = 11 THEN 'INCOME_DATA'
        WHEN id_document_type = 13 THEN 'ADDRESS'
    END AS document_type,
    CASE
        WHEN id_document_context = 1 THEN 'Owner'
        WHEN id_document_context = 2 THEN 'Tenant'
        WHEN id_document_context = 3 THEN 'Affiliate'
        WHEN id_document_context = 4 THEN 'Buyer'
        WHEN id_document_context = 5 THEN 'Seller'
    END AS document_context,
    GET_JSON_OBJECT(attributes, '$.grossIncome') AS monthly_salary,
    GET_JSON_OBJECT(attributes, '$.incomeNature.companyName') AS company_name,
    GET_JSON_OBJECT(attributes, '$.incomeNature.companyPhone') AS company_phone_number,
    GET_JSON_OBJECT(attributes, '$.incomeNatureType') AS emp_link,
    GET_JSON_OBJECT(attributes, '$.incomeNature.profession') AS profession,
    GET_JSON_OBJECT(attributes, '$.incomeNature.additionalGrossIncome') AS additional_income,
    GET_JSON_OBJECT(attributes, '$.incomeNature.additionalIncomeOrigin') AS source_of_income,
    GET_JSON_OBJECT(attributes, '$.incomeNature.additionalComments') AS documentation_extra_comment,
    GET_JSON_OBJECT(attributes, '$.incomeNature.payslips') AS payslips,
    GET_JSON_OBJECT(attributes, '$.incomeNature.ctpsPages') AS ctps_pages,
    GET_JSON_OBJECT(attributes, '$.incomeNature.bankStatements') AS bank_statements,
    NULLIF(attachments, '[]') AS attributes,
    NULLIF(attachments, '[]') AS attachments,
    ts_created,
    ts_updated
FROM
    datalake_docx_clean.document
WHERE
    id_document_type = 11