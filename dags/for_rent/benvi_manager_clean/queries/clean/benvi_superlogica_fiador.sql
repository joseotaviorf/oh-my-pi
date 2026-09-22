-- Widened to the full GUARANTOR payload so RAW fiadores in the extraction spreadsheet maps
-- one to one onto this projection.
-- nome_pes is the legacy alias of st_nome_pes, kept for existing consumers.
-- Personal and banking columns are projected on purpose; Trino column-level ACL
-- is the privacy control, not omission.
WITH guarantor_row AS (
    SELECT
        id,
        vendor_natural_key,
        CAST(payload AS STRING) AS payload_json,
        synced_at
    FROM
        datalake_benvi_manager_raw.lake_mirror
    WHERE
        resource_code = 'GUARANTOR'
)
SELECT
    id,
    vendor_natural_key AS id_pessoa_pes,
    get_json_object(payload_json, '$.st_nome_pes') AS nome_pes,
    get_json_object(payload_json, '$.st_nome_pes') AS st_nome_pes,
    get_json_object(payload_json, '$.st_cnpj_pes') AS st_cnpj_pes,
    get_json_object(payload_json, '$.st_fantasia_pes') AS st_fantasia_pes,
    get_json_object(payload_json, '$.st_rg_pes') AS st_rg_pes,
    get_json_object(payload_json, '$.st_orgao_pes') AS st_orgao_pes,
    get_json_object(payload_json, '$.st_ie_pes') AS st_ie_pes,
    get_json_object(payload_json, '$.st_inscmunicipal_pes') AS st_inscmunicipal_pes,
    get_json_object(payload_json, '$.st_endereco_pes') AS st_endereco_pes,
    get_json_object(payload_json, '$.st_complemento_pes') AS st_complemento_pes,
    get_json_object(payload_json, '$.st_numero_pes') AS st_numero_pes,
    get_json_object(payload_json, '$.st_cidade_pes') AS st_cidade_pes,
    get_json_object(payload_json, '$.st_estado_pes') AS st_estado_pes,
    get_json_object(payload_json, '$.st_cep_pes') AS st_cep_pes,
    get_json_object(payload_json, '$.st_bairro_pes') AS st_bairro_pes,
    get_json_object(payload_json, '$.st_pais_pes') AS st_pais_pes,
    get_json_object(payload_json, '$.st_telefone_pes') AS st_telefone_pes,
    get_json_object(payload_json, '$.st_celular_pes') AS st_celular_pes,
    get_json_object(payload_json, '$.st_email_pes') AS st_email_pes,
    get_json_object(payload_json, '$.st_observacao_pes') AS st_observacao_pes,
    get_json_object(payload_json, '$.st_nacionalidade_pes') AS st_nacionalidade_pes,
    get_json_object(payload_json, '$.st_sexo_pes') AS st_sexo_pes,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_nascimento_pes'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_nascimento_pes'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_nascimento_pes,
    get_json_object(payload_json, '$.st_estadocivil_pes') AS st_estadocivil_pes,
    get_json_object(payload_json, '$.st_profissao_pes') AS st_profissao_pes,
    get_json_object(payload_json, '$.st_ramoatividade_pes') AS st_ramoatividade_pes,
    get_json_object(payload_json, '$.st_trabalhocep_pes') AS st_trabalhocep_pes,
    get_json_object(payload_json, '$.st_trabalhoendereco_pes') AS st_trabalhoendereco_pes,
    get_json_object(payload_json, '$.st_trabalhonumero_pes') AS st_trabalhonumero_pes,
    get_json_object(payload_json, '$.st_trabalhocomplemento_pes') AS st_trabalhocomplemento_pes,
    get_json_object(payload_json, '$.st_trabalhobairro_pes') AS st_trabalhobairro_pes,
    get_json_object(payload_json, '$.st_trabalhocidade_pes') AS st_trabalhocidade_pes,
    get_json_object(payload_json, '$.st_trabalhoestado_pes') AS st_trabalhoestado_pes,
    get_json_object(payload_json, '$.st_banco_pes') AS st_banco_pes,
    get_json_object(payload_json, '$.id_forma_pag') AS id_forma_pag,
    get_json_object(payload_json, '$.st_agenciabanco_pes') AS st_agenciabanco_pes,
    get_json_object(payload_json, '$.st_conta_pes') AS st_conta_pes,
    get_json_object(payload_json, '$.id_sacado_sac') AS id_sacado_sac,
    get_json_object(payload_json, '$.id_favorecido_fav') AS id_favorecido_fav,
    CAST(get_json_object(payload_json, '$.fl_proprietariobeneficiario_pes') AS INT) AS fl_proprietariobeneficiario_pes,
    CAST(get_json_object(payload_json, '$.fl_locatario_pes') AS INT) AS fl_locatario_pes,
    CAST(get_json_object(payload_json, '$.fl_corretor_pes') AS INT) AS fl_corretor_pes,
    CAST(get_json_object(payload_json, '$.fl_fiador_pes') AS INT) AS fl_fiador_pes,
    get_json_object(payload_json, '$.st_nomerecebedor_pes') AS st_nomerecebedor_pes,
    get_json_object(payload_json, '$.st_cnpjrecebedor_pes') AS st_cnpjrecebedor_pes,
    get_json_object(payload_json, '$.id_formarecebimento_pes') AS id_formarecebimento_pes,
    get_json_object(payload_json, '$.st_identificadorprop_pes') AS st_identificadorprop_pes,
    get_json_object(payload_json, '$.st_identificadorloc_pes') AS st_identificadorloc_pes,
    CAST(get_json_object(payload_json, '$.vl_rendamensal_pes') AS DOUBLE) AS vl_rendamensal_pes,
    get_json_object(payload_json, '$.st_nome_coj') AS st_nome_coj,
    get_json_object(payload_json, '$.st_cpf_coj') AS st_cpf_coj,
    get_json_object(payload_json, '$.st_rg_coj') AS st_rg_coj,
    get_json_object(payload_json, '$.st_nacionalidade_coj') AS st_nacionalidade_coj,
    get_json_object(payload_json, '$.st_sexo_coj') AS st_sexo_coj,
    get_json_object(payload_json, '$.st_profissao_coj') AS st_profissao_coj,
    get_json_object(payload_json, '$.st_celular_coj') AS st_celular_coj,
    get_json_object(payload_json, '$.st_email_coj') AS st_email_coj,
    get_json_object(payload_json, '$.st_observacao_coj') AS st_observacao_coj,
    get_json_object(payload_json, '$.st_telefone_coj') AS st_telefone_coj,
    CAST(get_json_object(payload_json, '$.fl_status_pes') AS INT) AS fl_status_pes,
    get_json_object(payload_json, '$.nm_dependentes_pes') AS nm_dependentes_pes,
    get_json_object(payload_json, '$.st_tipoconta_pes') AS st_tipoconta_pes,
    get_json_object(payload_json, '$.id_unidade_uni') AS id_unidade_uni,
    get_json_object(payload_json, '$.st_nomeresp_pes') AS st_nomeresp_pes,
    get_json_object(payload_json, '$.st_cpfresp_pes') AS st_cpfresp_pes,
    get_json_object(payload_json, '$.st_telefoneresp_pes') AS st_telefoneresp_pes,
    get_json_object(payload_json, '$.st_respcep_pes') AS st_respcep_pes,
    get_json_object(payload_json, '$.st_respendereco_pes') AS st_respendereco_pes,
    get_json_object(payload_json, '$.st_respnumero_pes') AS st_respnumero_pes,
    get_json_object(payload_json, '$.st_respcomplemento_pes') AS st_respcomplemento_pes,
    get_json_object(payload_json, '$.st_respbairro_pes') AS st_respbairro_pes,
    get_json_object(payload_json, '$.st_respcidade_pes') AS st_respcidade_pes,
    get_json_object(payload_json, '$.st_respestado_pes') AS st_respestado_pes,
    get_json_object(payload_json, '$.st_respemail_pes') AS st_respemail_pes,
    get_json_object(payload_json, '$.st_rgresp_pes') AS st_rgresp_pes,
    get_json_object(payload_json, '$.st_identificadorfiador_pes') AS st_identificadorfiador_pes,
    get_json_object(payload_json, '$.st_orgao_coj') AS st_orgao_coj,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_expedicaorg_pes'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_expedicaorg_pes'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_expedicaorg_pes,
    get_json_object(payload_json, '$.st_operacao_pes') AS st_operacao_pes,
    CAST(get_json_object(payload_json, '$.fl_reterissqn_pes') AS INT) AS fl_reterissqn_pes,
    CAST(get_json_object(payload_json, '$.fl_reterinss_pes') AS INT) AS fl_reterinss_pes,
    CAST(get_json_object(payload_json, '$.fl_reterirrf_pes') AS INT) AS fl_reterirrf_pes,
    CAST(get_json_object(payload_json, '$.fl_reterpis_pes') AS INT) AS fl_reterpis_pes,
    CAST(get_json_object(payload_json, '$.fl_retercofins_pes') AS INT) AS fl_retercofins_pes,
    CAST(get_json_object(payload_json, '$.fl_retercontribuicaosocial_pes') AS INT) AS fl_retercontribuicaosocial_pes,
    get_json_object(payload_json, '$.st_razaoempresa_pes') AS st_razaoempresa_pes,
    get_json_object(payload_json, '$.st_telefoneempresa_pes') AS st_telefoneempresa_pes,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_admissaoempresa_pes'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_admissaoempresa_pes'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_admissaoempresa_pes,
    CAST(get_json_object(payload_json, '$.fl_naodomiciliado_pes') AS INT) AS fl_naodomiciliado_pes,
    CAST(get_json_object(payload_json, '$.fl_comprador_pes') AS INT) AS fl_comprador_pes,
    CAST(get_json_object(payload_json, '$.fl_vistoriador_pes') AS INT) AS fl_vistoriador_pes,
    get_json_object(payload_json, '$.st_identificadorcorretor_pes') AS st_identificadorcorretor_pes,
    get_json_object(payload_json, '$.id_foto_pes') AS id_foto_pes,
    get_json_object(payload_json, '$.st_creci_pes') AS st_creci_pes,
    CAST(get_json_object(payload_json, '$.vl_txissqn_pes') AS DOUBLE) AS vl_txissqn_pes,
    get_json_object(payload_json, '$.st_identidadeblockchain_pes') AS st_identidadeblockchain_pes,
    CAST(get_json_object(payload_json, '$.fl_naonotificar_pes') AS INT) AS fl_naonotificar_pes,
    get_json_object(payload_json, '$.st_fotourl_pes') AS st_fotourl_pes,
    get_json_object(payload_json, '$.st_nomemae_pes') AS st_nomemae_pes,
    get_json_object(payload_json, '$.st_nomepai_pes') AS st_nomepai_pes,
    get_json_object(payload_json, '$.st_naturalidade_pes') AS st_naturalidade_pes,
    CAST(get_json_object(payload_json, '$.fl_statusconvitecartao_pes') AS INT) AS fl_statusconvitecartao_pes,
    CAST(get_json_object(payload_json, '$.vl_tarifabancaria_pes') AS DOUBLE) AS vl_tarifabancaria_pes,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_diarepasse_pes'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_diarepasse_pes'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_diarepasse_pes,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_atualizacao_pes'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_atualizacao_pes'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_atualizacao_pes,
    CAST(get_json_object(payload_json, '$.fl_testemunha_pes') AS INT) AS fl_testemunha_pes,
    CAST(get_json_object(payload_json, '$.fl_contapessoa_pes') AS INT) AS fl_contapessoa_pes,
    CAST(get_json_object(payload_json, '$.fl_gerente_pes') AS INT) AS fl_gerente_pes,
    CAST(get_json_object(payload_json, '$.fl_reembolsoiss_pes') AS INT) AS fl_reembolsoiss_pes,
    CAST(get_json_object(payload_json, '$.fl_recolhimentodarf_pes') AS INT) AS fl_recolhimentodarf_pes,
    get_json_object(payload_json, '$.id_gestor_ges') AS id_gestor_ges,
    CAST(get_json_object(payload_json, '$.vl_saldobloqueado_pes') AS DOUBLE) AS vl_saldobloqueado_pes,
    CAST(get_json_object(payload_json, '$.fl_reembolsarirrf_pes') AS INT) AS fl_reembolsarirrf_pes,
    CAST(get_json_object(payload_json, '$.fl_reembolsarpiscofins_pes') AS INT) AS fl_reembolsarpiscofins_pes,
    CAST(get_json_object(payload_json, '$.fl_tipochavepix_pes') AS INT) AS fl_tipochavepix_pes,
    get_json_object(payload_json, '$.st_chavepix_pes') AS st_chavepix_pes,
    CAST(get_json_object(payload_json, '$.fl_descontosimplificadoir_pes') AS INT) AS fl_descontosimplificadoir_pes,
    get_json_object(payload_json, '$.st_codigocontabil_pes') AS st_codigocontabil_pes,
    CAST(get_json_object(payload_json, '$.fl_semrenda_pes') AS INT) AS fl_semrenda_pes,
    CAST(get_json_object(payload_json, '$.fl_vinculoemprego_pes') AS INT) AS fl_vinculoemprego_pes,
    get_json_object(payload_json, '$.st_beneficio_pes') AS st_beneficio_pes,
    CAST(get_json_object(payload_json, '$.vl_outrosrendimentos_pes') AS DOUBLE) AS vl_outrosrendimentos_pes,
    get_json_object(payload_json, '$.st_cnpjempresa_pes') AS st_cnpjempresa_pes,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_admissaoemprego_pes'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_admissaoemprego_pes'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_admissaoemprego_pes,
    get_json_object(payload_json, '$.st_enviodemonstrativoemail_pes') AS st_enviodemonstrativoemail_pes,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_enviodemonstrativo_pes'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_enviodemonstrativo_pes'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_enviodemonstrativo_pes,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_enviodemonstrativoinicio_pes'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_enviodemonstrativoinicio_pes'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_enviodemonstrativoinicio_pes,
    COALESCE(
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_enviodemonstrativofim_pes'), 1, 10), 'MM/dd/yyyy'),
        TO_DATE(SUBSTR(get_json_object(payload_json, '$.dt_enviodemonstrativofim_pes'), 1, 10), 'yyyy-MM-dd')
    ) AS dt_enviodemonstrativofim_pes,
    get_json_object(payload_json, '$.nome_formatado') AS nome_formatado,
    get_json_object(payload_json, '$.contratos') AS contratos,
    synced_at AS ts_synced
FROM
    guarantor_row
