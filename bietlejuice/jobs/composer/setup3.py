from setuptools import setup, find_packages

with open('requirements3.txt') as f:
    install_requires = [line for line in f.read().splitlines() if len(line) > 0]

setup(
    name='bi-etl-ejuice',
    version='0.1.0',
    description='bi-etl-ejuice module',
    author='Data Team',
    packages=find_packages(),
    install_requires=install_requires
)
