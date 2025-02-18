from enum import Enum


class UDFEnum(Enum):
    """
    Mapping of bi-etl-ejuice UDFs types to an Enum object.
    """

    SF_REMOVE_ACCENTUATION = "SF_REMOVE_ACCENTUATION"
    SF_ALPHANUMERIC_SNAKE_CASE = "SF_ALPHANUMERIC_SNAKE_CASE"
    SF_NORMALIZE_STRING = "SF_NORMALIZE_STRING"
    FINTECHOPS_WORK_MIN_SLA = "FINTECHOPS_WORK_MIN_SLA"
    FINTECH_COLLECTIONS_RENEGOTIATION = "FINTECH_COLLECTIONS_RENEGOTIATION"
    GET_PROFILING_DATA_QUALITY = "GET_PROFILING_DATA_QUALITY"
    GROWTH_VESPUCIO_SCORE = "GROWTH_VESPUCIO_SCORE"

    @classmethod
    def get_available_enum_values(cls):
        return [member.value for member in cls]

    @classmethod
    def get_udf(cls, udf_identifier: str):
        """
        Returns a method to be used as UDF, based on the UDF identifier provided.
        :param udf_identifier: a string representing the UDF identifier. Also used
            to call the respective function inside SQL queries. Must be mapped as
            an Enum within this class, otherwise a `ValueError` is raised.
        :type udf_identifier: str
        :return: callable
        """
        from bietlejuice.formatters.string_formatter import StringFormatter
        from bietlejuice.base.udfs.fintech import FintechUDFs
        from bietlejuice.base.udfs.governance import ProfilingFromYaml
        from bietlejuice.base.udfs.growth import VespucioScoreCalculator

        udf_enum_member = cls(udf_identifier)

        return {
            cls.SF_REMOVE_ACCENTUATION: StringFormatter.replace_accents,
            cls.SF_ALPHANUMERIC_SNAKE_CASE: StringFormatter.set_alphanumeric_snake_case,
            cls.SF_NORMALIZE_STRING: StringFormatter.normalize_string,
            cls.FINTECHOPS_WORK_MIN_SLA: FintechUDFs.fintechops_work_min_sla,
            cls.FINTECH_COLLECTIONS_RENEGOTIATION: FintechUDFs.fintech_collections_renegotiation,
            cls.GET_PROFILING_DATA_QUALITY: ProfilingFromYaml.get_profiling_data_quality,
            cls.GROWTH_VESPUCIO_SCORE: VespucioScoreCalculator.get_score,
        }.get(udf_enum_member)
