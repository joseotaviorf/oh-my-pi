-- Roll-Up catalogue of the distinct checklist templates seen on contracts.
-- Reproduces build_all_checklists in dw_modeling.py: distinct id and name pairs,
-- trimmed, with empty ids or names dropped.
-- Modelled table, not a vendor mirror, hence the benvi_rollup_ prefix. It stays in
-- this DAG and layer because it is pure derivation over the clean projections.
SELECT DISTINCT
    TRIM(checklist_item.id_checklist_chk) AS id_checklist_chk,
    TRIM(checklist_item.st_nome_chk) AS st_nome_chk
FROM
    datalake_benvi_manager_clean.benvi_superlogica_checklist_contrato AS checklist_item
WHERE
    TRIM(COALESCE(checklist_item.id_checklist_chk, '')) <> ''
    AND TRIM(COALESCE(checklist_item.st_nome_chk, '')) <> ''
