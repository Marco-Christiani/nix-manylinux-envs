import os
import shlex

from setuptools import Extension, setup


dist_name = os.environ.get("BASELINE_PROBE_DIST_NAME", "manylinux-baseline-probe")
extra_compile_args = ["-std=c++17"] + shlex.split(
    os.environ.get("BASELINE_PROBE_EXTRA_COMPILE_ARGS", "")
)

setup(
    name=dist_name,
    version="0.1.0",
    ext_modules=[
        Extension(
            "baseline_probe._core",
            ["src/baseline_probe/_core.cpp"],
            language="c++",
            extra_compile_args=extra_compile_args,
            libraries=["z"],
        )
    ],
    packages=["baseline_probe"],
    package_dir={"": "src"},
)
