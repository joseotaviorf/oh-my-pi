-- PII: st_solicitante_tic, st_solicitante_tic_formatado, st_responsavel_tic,
-- st_nome_usu, st_nome_fav are person names, and st_telefone_tic, st_celular_tic,
-- st_fax_tic, st_copia_tic are contact channels. Projected like the debtor columns
-- on benvi_superlogica_cobranca: clean carries the field, Trino column-level ACL is
-- the access control.
-- Join id_solicitante_tic to locatario or proprietario (type in fl_tiposolicitante_tic).
-- Join nome_grpu to departamento.nome_grpu; USER_GROUP has no vendor id in the API.
SELECT
    id,
    vendor_natural_key AS id_ticket_tic,
    get_json_object(CAST(payload AS STRING), '$.id_solicitante_tic') AS id_solicitante_tic,
    CAST(get_json_object(CAST(payload AS STRING), '$.fl_tiposolicitante_tic') AS INT) AS fl_tiposolicitante_tic,
    get_json_object(CAST(payload AS STRING), '$.st_solicitante_tic') AS st_solicitante_tic,
    get_json_object(CAST(payload AS STRING), '$.st_solicitante_tic_formatado') AS st_solicitante_tic_formatado,
    get_json_object(CAST(payload AS STRING), '$.id_responsavel_tic') AS id_responsavel_tic,
    get_json_object(CAST(payload AS STRING), '$.st_responsavel_tic') AS st_responsavel_tic,
    get_json_object(CAST(payload AS STRING), '$.st_nome_usu') AS st_nome_usu,
    get_json_object(CAST(payload AS STRING), '$.id_grupo_tic') AS id_grupo_tic,
    get_json_object(CAST(payload AS STRING), '$.st_nome_grpu') AS nome_grpu,
    get_json_object(CAST(payload AS STRING), '$.id_cliente_tic') AS id_cliente_tic,
    get_json_object(CAST(payload AS STRING), '$.id_condominio_cond') AS id_condominio_cond,
    get_json_object(CAST(payload AS STRING), '$.id_favorecido_fav') AS id_favorecido_fav,
    get_json_object(CAST(payload AS STRING), '$.st_nome_fav') AS st_nome_fav,
    get_json_object(CAST(payload AS STRING), '$.st_nome_tca') AS nome_tca,
    get_json_object(CAST(payload AS STRING), '$.st_titulo_tic') AS titulo_tic,
    get_json_object(CAST(payload AS STRING), '$.st_historico_tih') AS historico_tih,
    get_json_object(CAST(payload AS STRING), '$.anexos') AS anexos,
    get_json_object(CAST(payload AS STRING), '$.st_telefone_tic') AS st_telefone_tic,
    get_json_object(CAST(payload AS STRING), '$.st_celular_tic') AS st_celular_tic,
    get_json_object(CAST(payload AS STRING), '$.st_fax_tic') AS st_fax_tic,
    get_json_object(CAST(payload AS STRING), '$.st_copia_tic') AS st_copia_tic,
    CAST(get_json_object(CAST(payload AS STRING), '$.fl_status_tic') AS INT) AS fl_status_tic,
    CAST(get_json_object(CAST(payload AS STRING), '$.fl_interno_tic') AS INT) AS fl_interno_tic,
    get_json_object(CAST(payload AS STRING), '$.atrasado') AS atrasado,
    get_json_object(CAST(payload AS STRING), '$.horas_atrasado') AS horas_atrasado,
    TO_DATE(get_json_object(CAST(payload AS STRING), '$.dt_ticket_tic')) AS dt_ticket_tic,
    TO_DATE(get_json_object(CAST(payload AS STRING), '$.dt_inicioticket_tic')) AS dt_inicioticket_tic,
    TO_DATE(get_json_object(CAST(payload AS STRING), '$.dt_encerrado_tic')) AS dt_encerrado_tic,
    synced_at AS ts_synced
FROM
    datalake_benvi_manager_raw.lake_mirror
WHERE
    resource_code = 'TICKET'
