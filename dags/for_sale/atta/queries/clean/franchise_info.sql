SELECT
    ID AS id_franchise,
    IDUsuCad AS id_registration_user,
    Status AS id_franchise_status,
    Nome AS franchise_name,
    CategoriaFranquia AS franchise_category,
    TpFranquia AS franchise_type,
    despachante AS fowarding,
    CASE
        WHEN despachante IS FALSE THEN 'retail'
        WHEN despachante IS TRUE THEN 'hubs'
    END AS fowarding_type,
    PercRoyalties AS royalties_percentage_value,
    PercFundoMarketing AS martketing_fund_percentage,
    CarenciaRoyalties AS grace_period_royalties,
    CarenciaTec AS grace_period_tec,
    PrazoContrato AS ts_contract_deadline,
    TIMESTAMP(DtCadastro) AS ts_registration,
    TIMESTAMP(DtAssinatura) AS ts_franchise_signature
FROM
    datalake_atta_raw.franquia
