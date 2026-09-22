-- Vendor dates arrive as MM/dd/yyyy, so TO_DATE needs the format;
-- without it every date column on this projection landed null.
-- USER_GROUP exposes no vendor id on the list endpoint, so the group name is the
-- vendor_natural_key. id_grupo_grpu, fl_visivelparaclientes_grpu, st_acessos_grpu and
-- dt_deletadoem_grpu are carried in the payload as unmapped vendor fields.
-- id_grupo_grpu is the id that benvi_superlogica_ticket.id_grupo_tic points at.
-- Renaming a group in Superlogica orphans the row landed under the old name.
SELECT
    id,
    vendor_natural_key AS nome_grpu,
    get_json_object(CAST(payload AS STRING), '$.id_grupo_grpu') AS id_grupo_grpu,
    get_json_object(CAST(payload AS STRING), '$.totalusuarios') AS total_usuarios,
    get_json_object(CAST(payload AS STRING), '$.st_acessos_grpu') AS st_acessos_grpu,
    get_json_object(CAST(payload AS STRING), '$.fl_visivelparaclientes_grpu') AS fl_visivelparaclientes_grpu,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(CAST(payload AS STRING), '$.dt_deletadoem_grpu'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(CAST(payload AS STRING), '$.dt_deletadoem_grpu'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_deletadoem_grpu,
    synced_at AS ts_synced
FROM
    datalake_benvi_manager_raw.lake_mirror
WHERE
    resource_code = 'USER_GROUP'
