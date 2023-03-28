SELECT 
    id_proponent,
    id_proposal,
    cpf,
    id_proponent_docx,
    id_proponent_sorting_hat,
    id_proponent_ebdb
FROM datalake_proponent.proponent 
WHERE is_main_proponent = TRUE