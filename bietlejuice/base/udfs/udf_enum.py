from enum import Enum


class UDFEnum(Enum):
    """
    Mapping of bi-etl-ejuice UDFs types to an Enum object.
    """

    SF_REMOVE_ACCENTUATION = "SF_REMOVE_ACCENTUATION"
    SF_ALPHANUMERIC_SNAKE_CASE = "SF_ALPHANUMERIC_SNAKE_CASE"
    FINTECHOPS_WORK_MIN_SLA = "FINTECHOPS_WORK_MIN_SLA"

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

        udf_enum_member = cls(udf_identifier)

        return {
            cls.SF_REMOVE_ACCENTUATION: StringFormatter.replace_accents,
            cls.SF_ALPHANUMERIC_SNAKE_CASE: StringFormatter.set_alphanumeric_snake_case,
            cls.FINTECHOPS_WORK_MIN_SLA: FintechUDFs.fintechops_work_min_sla,
        }.get(udf_enum_member)
