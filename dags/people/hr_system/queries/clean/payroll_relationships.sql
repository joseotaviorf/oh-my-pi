SELECT
  OverridingPeriodId AS id_overriding_period,
  PartyId AS id_party,
  PayrollRelationshipId AS id_payroll_relationship,
  Country AS country,
  PayrollRelationshipNumber AS payroll_relationship_number,
  PersonNumber AS person_number,
  PartyNumber AS party_number,
  PayRelationshipsDDF AS pay_relationships,
  payrollAssignments AS payroll_assignments,
  payrollRelationshipDates AS payroll_relationship_dates,
  StartDate AS dt_start,
  EndDate AS dt_end,
  EffectiveStartDate AS dt_effective_start,
  EffectiveEndDate AS dt_effective_end,
  ts_load
FROM
  datalake_hr_system_raw.payroll_relationships