WITH contract_users AS (
    SELECT
	    id AS id_contract,
	    id_user
    FROM
        datalake_ebdb_clean.contract
    UNION ALL
    SELECT
        c.id AS id_contract,
        h.id_user AS id_user
    FROM
        datalake_ebdb_clean.contract AS c
    INNER JOIN
        datalake_ebdb_clean.house AS h
            ON h.id = c.id_house
),
contract_cpfs AS (
    SELECT
    	id_contract,
    	cpf
    FROM
        datalake_ebdb_clean.contract_person
),
ongoing_contracts AS (
    SELECT
    	id AS id_contract,
    	CASE
            WHEN status IN ('Ativo','Finalizado')
                AND type <> 'DealOnly'
                AND current_date >= COALESCE(DATE(ts_signed), dt_started, dt_entered)
                AND (current_date < dt_termination OR dt_termination IS NULL) THEN TRUE
    	        ELSE FALSE
        END AS is_ongoing_contract
    FROM
        datalake_ebdb_clean.contract
),
users_ongoing AS (
    SELECT
    	c.id_user,
    	MAX(oc.id_contract) AS id_max_ongoing_contract
    FROM
        contract_users AS c
        INNER JOIN
            ongoing_contracts AS oc
                ON c.id_contract = oc.id_contract
    WHERE
        oc.is_ongoing_contract = TRUE
    GROUP BY 1
),
cpfs_ongoing AS (
    SELECT
        cc.cpf,
        MAX(oc.id_contract) AS id_max_ongoing_contract
    FROM
        contract_cpfs AS cc
        INNER JOIN
            ongoing_contracts AS oc
                ON cc.id_contract = oc.id_contract
    WHERE
        oc.is_ongoing_contract = TRUE
    GROUP BY 1
)
SELECT 
    cp.id AS id_contract_person,
    cp.id_user AS id_user_contract_person,
    uo.id_user,
    uo.id_max_ongoing_contract AS id_max_ongoing_contract_user,
    co.id_max_ongoing_contract AS id_max_ongoig_contract_cpf,
    cp.name AS full_name,
    cp.cpf AS personal_document,
    cp.phone_number,
    cp.email,
    cp.state_id AS state_code,
    COALESCE(uo.id_max_ongoing_contract, co.id_max_ongoing_contract) > 0 AS has_ongoing_contract,
    cp.dt_birth,
    cp.ts_created,
    cp.ts_updated
FROM
    datalake_ebdb_clean.contract_person AS cp
    LEFT JOIN 
        users_ongoing AS uo
            ON uo.id_user = cp.id_user
    LEFT JOIN
        cpfs_ongoing AS co
            ON co.cpf = cp.cpf