from bietlejuice.jobs.composer.formatters import StringFormatter

USER_DEFINED_FUNCTIONS = {
    "SF_REMOVE_ACCENTUATION": StringFormatter.replace_accents,
    "SF_ALPHANUMERIC_SNAKE_CASE": StringFormatter.set_alphanumeric_snake_case
}