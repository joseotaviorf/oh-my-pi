# TODO allow handler to be chosen (file or stream)
# TODO fix nested decorators losing class name
# TODO overwrite message methods (info, warning...) to have a standard message

import logging


class QuintoAndarLogger(logging.Logger):
    """This class implements a default logger for QuintoAndar and has some
    additions to how logging.Logger works:
        - format can be set when instantiating an object.
        - an object of this class can be used as a decorator to show logs a
            function call.
    """

    def __init__(
        self,
        name="root",
        level=logging.INFO,
        fmt="%(levelname)s:%(name)s:%(asctime)s:%(message)s",
        datefmt=None,
    ):
        super(QuintoAndarLogger, self).__init__(name, level)

        # create a handler for the logger object
        stream_handler = logging.StreamHandler()

        # create a formatter
        formatter = logging.Formatter(fmt=fmt, datefmt=datefmt)

        # set format to the handler
        stream_handler.setFormatter(formatter)

        # set handler to be used
        self.addHandler(stream_handler)

    def __call__(self, func=None, exclude=None, exclude_return=False):
        """
        Usage:
            @logger
            def some_function([cls, self, None], x, y):
                pass

            @logger(exclude='x')
            def some_function(x, y):
                pass

            @logger(exclude=['x', 'y']):
            def some_function(x, y):
                pass

            @logger(exclude_return=True)
            def some_function():
                pass

        :param func: function to be logged
        :param exclude: param names to be excluded in the logging string
        :param exclude_return: sets if the returned value of the function is going to be
        excluded of the logging string. This param is false by default.
        :return: complete logging string
        """

        def _wrapper(*args, **kwargs):
            # gets the method name
            method_name = "unnamed"
            if hasattr(func, "__name__"):
                method_name = func.__name__

            # gets the class name
            class_name = "unnamed"
            if args and "cls" in func.__code__.co_varnames[0]:
                class_name = args[0].__name__
            elif args and "self" in func.__code__.co_varnames[0]:
                class_name = args[0].__class__.__name__
            elif hasattr(func, "__class__"):
                class_name = func.__class__.__name__

            prefix_str = "m={}.{}".format(class_name, method_name)
            params_str = ""

            if args:
                for index, arg in enumerate(args):
                    if index >= func.__code__.co_argcount:
                        params_str += ", {}".format(args[index])
                    else:
                        arg_name = func.__code__.co_varnames[index]
                        if (
                            "self" in arg_name
                            or "cls" in arg_name
                            or (exclude and arg_name in exclude)
                        ):
                            continue
                        else:
                            params_str += ", {}={}".format(arg_name, arg)

            if kwargs:
                for key, val in kwargs.items():
                    if not exclude or key not in exclude:
                        params_str += ", {}={}".format(key, val)

            self.info(prefix_str + params_str)

            try:
                return_value = func(*args, **kwargs)
            except Exception as e:
                self.exception("m={}, msg={}".format(method_name, e))
                raise e

            if return_value is not None and not exclude_return:
                self.info(prefix_str + ", returned_value={}".format(return_value))

            return return_value

        def _partial_wrapper(func):
            return self(func, exclude)

        if func is None:
            return _partial_wrapper
        else:
            return _wrapper
