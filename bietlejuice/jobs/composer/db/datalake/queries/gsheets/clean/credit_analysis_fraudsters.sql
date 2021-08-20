SELECT
    CAST(id_house AS INTEGER ) AS id_house,
    cpf,
    email,
    login,
    name,
    phone,
    rejection_reason,
    TO_DATE(date_occurence, 'dd/mm/yyyy') AS dt_occurence
FROM
    datalake_gsheets_raw.credit_analysis_fraudsters