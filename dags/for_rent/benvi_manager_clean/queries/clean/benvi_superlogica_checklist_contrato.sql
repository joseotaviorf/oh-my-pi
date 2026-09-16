-- Contract-linked: join to benvi_superlogica_contrato in downstream consumers.
SELECT
    id,
    vendor_natural_key AS vendor_natural_key,
    split(vendor_natural_key, '\\\\|')[0] AS id_contrato_con,
    split(vendor_natural_key, '\\\\|')[1] AS id_checklist_chk,
    split(vendor_natural_key, '\\\\|')[2] AS id_checklistitem_chi,
    synced_at AS ts_synced
FROM
    datalake_benvi_manager_raw.lake_mirror
WHERE
    resource_code = 'CONTRACT_CHECKLIST_ITEM'
