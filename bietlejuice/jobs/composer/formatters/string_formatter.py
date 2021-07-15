import re
from unidecode import unidecode


class StringFormatter:
    @classmethod
    def set_alphanumeric_snake_case(cls, str_value: str) -> str:
        """
        Returns the string in alphanumerical non-accentuated snake case format.
        e.g.: 0ne ínPut*StrInG => 0ne_inputstring
        """
        str_value = cls.remove_symbols(str_value)
        str_value = cls.set_snake_case(str_value)
        str_value = cls.replace_accents(str_value)
        return str_value

    @staticmethod
    def slugify(str_value: str) -> str:
        """
        Returns a slugified string (Normal Case => slug-case) string.
        """
        return str_value.replace("_", "-").lower()

    @staticmethod
    def remove_symbols(str_value: str) -> str:
        """
        Removes symbols like * " / returning only spaced alphanumeric charaters.
        """
        return re.sub(r"[^\w\s]", "", str_value)

    @staticmethod
    def set_snake_case(str_value: str) -> str:
        """
        Returns the string in snake case (NoRmal Case => snake_case) format.
        """
        return re.sub(r"\s+", "_", str_value).lower()

    @staticmethod
    def replace_accents(str_value: str) -> str:
        """
        Replaces an accented charater by its respective non-accented character.
        """
        return unidecode(str_value)
