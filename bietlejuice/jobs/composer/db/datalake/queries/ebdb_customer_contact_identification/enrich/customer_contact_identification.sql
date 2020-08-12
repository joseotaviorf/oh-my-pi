WITH user_emails AS (
	SELECT
		id_user,
		cpf,
		'email' AS channel,
		email AS customer_contact
	FROM datalake_ebdb_clean.user_aud
	WHERE email IS NOT NULL
	GROUP BY 1,2,3,4
),
user_alternative_emails AS (
	SELECT
		id_user,
		cpf,
		'email' AS channel,
		alternative_email AS customer_contact
	FROM datalake_ebdb_clean.user_aud
	WHERE alternative_email IS NOT NULL
	GROUP BY 1,2,3,4
),
user_main_phones AS (
	SELECT
		id_user,
		cpf,
		'phone' AS channel,
		REGEXP_REPLACE(main_phone,'(\D+)','') AS customer_contact
	FROM datalake_ebdb_clean.user_aud
	WHERE main_phone IS NOT NULL
	GROUP BY 1,2,3,4
),
user_secondary_phones AS (
	SELECT
		id_user,
		cpf,
		'phone' AS channel,
		REGEXP_REPLACE(secondary_phone,'(\D+)','') AS customer_contact
	FROM datalake_ebdb_clean.user_aud
	WHERE secondary_phone IS NOT NULL
	GROUP BY 1,2,3,4
),
all_user_contacts AS (
	SELECT * FROM user_emails
	UNION
	SELECT * FROM user_alternative_emails
	UNION
	SELECT * FROM user_main_phones
	UNION
	SELECT * FROM user_secondary_phones
),
-- avoid repeated contacts to obtain an 1:1 relation between contact and user (ex: phone numbers might be reused by other people)
user_contacts AS (
	SELECT
		customer_contact,
		channel,
		MAX(id_user) AS id_user
	FROM all_user_contacts
	WHERE customer_contact != ''
	GROUP BY 1,2
),
user_full_contacts AS (
	SELECT
		uc.customer_contact,
		uc.channel,
		uc.id_user,
		u.cpf AS cpf
	FROM user_contacts uc
	INNER JOIN datalake_ebdb_clean.user u
		ON uc.id_user = u.id
),
contract_people_emails AS (
	SELECT
		cpf,
		'email' AS channel,
		email AS customer_contact
	FROM datalake_ebdb_clean.contract_person_aud
	WHERE cpf IS NOT NULL
		AND email IS NOT NULL
	GROUP BY 1,2,3
),
contract_people_phone_numbers AS (
	SELECT
		cpf,
		'phone' AS channel,
		REPLACE(REGEXP_REPLACE(phone_number,'(\D+)',''),'+','') AS customer_contact
	FROM datalake_ebdb_clean.contract_person_aud
	WHERE cpf IS NOT NULL
		AND phone_number IS NOT NULL
	GROUP BY 1,2,3
),
contract_people_secondary_phones AS (
	SELECT
		cpf,
		'phone' AS channel,
		REPLACE(REGEXP_REPLACE(secondary_phone,'(\\D+)',''),'+','') AS customer_contact
	FROM datalake_ebdb_clean.contract_person_aud
	WHERE cpf IS NOT NULL
		AND secondary_phone IS NOT NULL
	GROUP BY 1,2,3
),
proposal_people_emails AS (
	SELECT
		cpf,
		'email' AS channel,
		email AS customer_contact
	FROM datalake_ebdb_clean.proponent_proposal_aud
	WHERE cpf IS NOT NULL
		AND email IS NOT NULL
	GROUP BY 1,2,3
),
proposal_people_phone_numbers AS (
	SELECT
		cpf,
		'phone' AS channel,
		REGEXP_REPLACE(phone_number,'(\\D+)','') AS customer_contact
	FROM datalake_ebdb_clean.proponent_proposal_aud
	WHERE cpf IS NOT NULL
		AND phone_number IS NOT NULL
	GROUP BY 1,2,3
),
all_person_contacts AS (
	SELECT * FROM contract_people_emails
	UNION
	SELECT * FROM contract_people_phone_numbers
	UNION
	SELECT * FROM contract_people_secondary_phones
	UNION
	SELECT * FROM proposal_people_emails
	UNION
	SELECT * FROM proposal_people_phone_numbers
),
-- avoid repeated contacts to obtain an 1:1 relation between contact and person (ex: phone numbers might be reused by other people)
person_contacts AS (
	SELECT
		customer_contact,
		channel,
		null as id_user,
		MAX(cpf) AS cpf
	FROM all_user_contacts
	WHERE customer_contact != ''
	GROUP BY 1,2,3
)
SELECT
	COALESCE(ufc.customer_contact,pc.customer_contact) AS customer_contact,
	COALESCE(ufc.channel, pc.channel) AS channel,
	MAX(ufc.id_user) AS id_user,
	MAX(COALESCE(ufc.cpf, pc.cpf)) AS cpf
FROM user_full_contacts ufc
FULL JOIN person_contacts pc
	ON ufc.customer_contact = pc.customer_contact
GROUP BY 1,2