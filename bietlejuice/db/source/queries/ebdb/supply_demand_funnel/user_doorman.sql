SELECT
	dad.id,
	dad.workAddress,
	dad.workStreet,
	dad.workHouseNumber,
	dad.workNeighbourhood,
	dad.workCity,
	dad.workState,
	dad.lat,
	dad.lng,
	dad.placeId,
	dad.code,
	dad.recruiter,
	dad.subscriptionSource,
	dad.doorman_occupation_id,
	dao.name as occupation_name,
	dad.atualizadoEm,
	dad.criadoEm,
	dad.joinedProgramAt,
	da.id,
	(da.doormanAffiliateData_id is not null
        and coalesce(da.affiliateType,'') = 'Doorman'
        and dad.joinedProgramAt is not null) as is_active
FROM
	DoormanAffiliateData dad
LEFT JOIN
	DadosAfiliado da
	ON da.doormanAffiliateData_id = dad.id
LEFT JOIN
    Usuario u
    ON u.dadosAfiliado_id = da.id
LEFT JOIN
  DoormanAffiliateOccupation dao
	ON dad.doorman_occupation_id = dao.id
