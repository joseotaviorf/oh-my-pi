from unidecode import unidecode


class StringFormatterUDF:
    """
    Class to group string formatter UDFs (user-defined functions) to use in spark
    """

    @staticmethod
    def remove_accentuation(string):
        """
        Remove accentuation from a string provided
        :param string: string to format
        :return: formatted string, without accentuation
        """
        return unidecode(string)
