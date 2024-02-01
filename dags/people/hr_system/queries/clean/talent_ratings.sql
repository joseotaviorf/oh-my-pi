SELECT
    ProfileId AS id_profile,
    PersonId AS id_person,
    ProfileCode AS profile_code,
    nBoxCellAssignments AS n_box_cell_assignments,
    performanceRatings AS performance_ratings,
    userDefinedRatingSections AS user_defined_rating_sections,
    ts_load
FROM datalake_hr_system_raw.talent_ratings