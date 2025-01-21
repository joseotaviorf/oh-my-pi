SELECT
    RERSSNUM AS id_client,
    RERACCT AS id_contract,
    RERNAME2 AS id_quintoandar,
    RERID AS id_phone,
    source,
    RERACCTG AS contract_group,
    CASE
        WHEN RERACCTG = "1" THEN "QuintoAndar"
        WHEN RERACCTG = "2" THEN "QuintoCred"
        ELSE RERACCTG
    END AS creditor,
    CASE
        WHEN RERDESC  = 1 THEN "Proprietario"
        WHEN RERDESC  = 2 THEN "Inquilino"
        WHEN RERDESC  = 8 THEN "Avalista"
        WHEN RERDESC  = 10 THEN "Fiador"
        WHEN RERDESC  = 12 THEN "Garantidor"
        WHEN RERDESC  = 15 THEN "Morador"
        WHEN RERDESC  = 20 THEN "Participante Empresa"
        ELSE RERDESC
    END  AS client_type,
    CASE
        WHEN RERSALCD = 1 THEN "Sr."
        WHEN RERSALCD = 2 THEN "Sra."
        ELSE RERSALCD
    END AS greeting,
    RERNAME AS name,
    RERADDR3 AS complement,
    RERNUMERORUA AS address_number,
    RERADDR1 AS address,
    RERADDR2 AS neighborhood,
    RERCITY AS city,
    RERSTATE AS state,
    RERZIP AS zip_code,
    RERSEQ AS sequence_number,
    RERPHONE AS personal_phone,
    RERBPHON AS business_phone,
    RERBEXT AS business_phone_extension,
    RERDTNASC AS dt_birth,
    RERNATURALID AS nationality,
    RERUFNATUR AS nationality_uf,
    RERNMPAI AS father_name,
    RERNMMAE AS mother_name,
    RERNACIONALI AS nationality_acronym,
    CASE
        WHEN RERESTCIVIL = "S" THEN "Solteiro"
        WHEN RERESTCIVIL = "C" THEN "Casado"
        WHEN RERESTCIVIL = "V" THEN "Viuvo"
        WHEN RERESTCIVIL = "D" THEN "Divorciado"
        WHEN RERESTCIVIL = "A" THEN "Amasiado"
        ELSE RERESTCIVIL
    END AS marital_status,
    RERCONJNOME AS partner_name,
    RERCONJNASC AS dt_birth_partner,
    RERFLACSPC AS has_spc_credit_denial,
    RERFLACSER AS has_serasa_credit_denial,
    RERFLACCDL AS has_internal_credit_denial,
    RERFLACBVS AS has_bvs_credit_denial,
    REREMAIL AS email,
    RERDTALTERACAO AS ts_update,
    RERDTINCLUSAO AS ts_insert,
    RERHISTDT AS ts_history,
    NOW() AS ts_load
FROM datalake_cyber_raw.relations
