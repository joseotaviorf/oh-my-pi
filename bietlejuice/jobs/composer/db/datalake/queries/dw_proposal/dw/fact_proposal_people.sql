SELECT
	pp.id_proposal_person AS sk_proposal_person,
	pp.id_personal_document AS sk_personal_document,
	COALESCE(u.id,-1) AS sk_proponent,
	pp.id_proposal AS sk_proposal,
	COALESCE(CAST(DATE_FORMAT(pp.dt_birth, 'yyyyMMdd') AS BIGINT), -1) AS sk_birth_date,
	COALESCE(CAST(DATE_FORMAT(pp.ts_created, 'yyyyMMdd') AS BIGINT), -1) AS sk_created_date,
	pp.expected_contract_role,
	pp.rental_motive,
    pp.brl_total_income,
	pp.is_going_to_live,
	pp.is_first_proposal,
	pp.is_last_proposal,
	CASE 
        WHEN u.id IS NOT NULL THEN true 
        ELSE false 
    END AS is_user,
	pp.is_valid_cpf,
	pp.is_valid_cnpj,
	NOW() AS ts_load
FROM 
    datalake_ebdb_proposal.proposal_person pp
INNER JOIN 
    datalake_ebdb_clean.proposal p
	    ON pp.id_proposal = p.id
LEFT JOIN 
    datalake_ebdb_clean.user u
	    ON p.id_proponent = u.id
	    AND pp.id_personal_document = u.cpf