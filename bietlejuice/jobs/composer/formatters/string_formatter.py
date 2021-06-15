class StringFormatter:
    @staticmethod
    def slugify(value: str) -> str:
        return value.replace("_", "-")
