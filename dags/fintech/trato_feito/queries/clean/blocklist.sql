SELECT
	id,
	external_id AS id_external,
	debtor_external_id AS id_debtor_external,
	debtor_id AS id_debtor,
	reason,
	blocked AS is_blocked,
	created_at AS ts_created,
	updated_at AS ts_updated
FROM
    datalake_trato_feito_raw.blocklist
