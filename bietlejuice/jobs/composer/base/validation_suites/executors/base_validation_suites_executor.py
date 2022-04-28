import inspect

from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("BaseValidationSuite")


class BaseValidationSuitesExecutor:
    """
    Validation suites executors abstract class.
    """

    SECRET_KEY = None
    REPOSITORY_CONSUMER_CLASS = None

    def __init__(self) -> None:
        self.auth = None
        self._suite_validation_has_failures = False

    def get_suite_validation_has_failures(self) -> bool:
        return self._suite_validation_has_failures

    def set_suite_validation_has_failures(self, state) -> None:
        self._suite_validation_has_failures = state

    def run(self) -> None:
        """
        This is the main method executed by the validation suites
         (E.g.: EBDBValidationSuite).
        It runs every validation_ custom test defined in the validation suite
         class. And the default ones defined in the executor class.

        Only stops when all validations are finished.
        """

        suite_validation_methods_names = [
            attr
            for attr in dir(self)
            if inspect.ismethod(getattr(self, attr)) and attr.startswith("validate_")
        ]
        suite_class_name = type(self).__name__

        logger.info(
            f"\n\nm=run, msg=::::::::::::::::: STARTING VALIDATIONS OF SUITE: {suite_class_name} :::::::::::::::::"
        )
        for validate_method_name in suite_validation_methods_names:
            logger.info(f"m=run, msg=:::: EXECUTING VALIDATION: {validate_method_name}")
            try:
                validate_method = getattr(self, validate_method_name)
                validate_method()

                logger.info("m=run, msg=:::: VALIDATION SUCCEEDED ::::")
            except Exception as e:
                self.set_suite_validation_has_failures(True)
                logger.error(e)
                logger.info(
                    f"m=run, msg=:::: VALIDATION {validate_method_name} FAILED (see log above for error details) ::::"
                )

        logger.info(
            f"m=run, msg=::::::::::::::::: FINISHED VALIDATIONS OF SUITE: {suite_class_name} :::::::::::::::::\n\n"
        )
