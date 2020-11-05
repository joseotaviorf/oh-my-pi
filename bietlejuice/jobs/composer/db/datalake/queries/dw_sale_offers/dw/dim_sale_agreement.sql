SELECT
	eso.id_offer AS sk_offer,
	eso.sale_agreement_status,
	eso.sale_agreement_cancellation_reason,
	eso.sale_price_agreed,
	eso.brokerage_fee,
	eso.fgts_value,
	eso.financing_bank,
	eso.financing_value,
	eso.earnest_value,
	CAST(eso.dt_sale_agreement_signed AS TIMESTAMP) AS ts_sale_agreement_signed,
	CAST(eso.dt_sale_agreement_cancelled AS TIMESTAMP) AS ts_sale_agreement_cancelled,
	CAST(eso.dt_house_registry_ended AS TIMESTAMP) AS ts_house_registry_ended,
	CAST(eso.dt_sale_transacton_paid AS TIMESTAMP) AS ts_sale_transacton_paid,
	now() AS ts_load
FROM datalake_offer.sale_offer eso
WHERE eso.dt_sale_agreement_signed IS NOT NULL