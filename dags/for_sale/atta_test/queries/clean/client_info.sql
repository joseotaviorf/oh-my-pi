SELECT
	id_cliente 	AS id_client,
	nm_cliente 	AS client_name,
	nr_cpf 		AS client_cpf,
	nm_email	AS client_email,
	nr_celular	AS client_cellphone,
	nr_telefone	AS client_phone
FROM
	datalake_atta_test_raw.cliente
