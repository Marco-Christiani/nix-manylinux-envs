{
  lib,
  pkgs,
  targetShell,
  mkManylinuxWheel,
  python ? pkgs.python312,
  suffix ? "cp312",
}: let
  src = pkgs.runCommand "mk-manylinux-wheel-smoke-src" {} ''
    mkdir -p "$out/src/smoke"

    cat > "$out/pyproject.toml" <<'EOF'
    [build-system]
    requires = ["setuptools", "wheel"]
    build-backend = "setuptools.build_meta"
    EOF

    cat > "$out/setup.py" <<'EOF'
    from setuptools import Extension, setup

    setup(
        name="mk-manylinux-wheel-smoke",
        version="0.1.0",
        packages=["smoke"],
        package_dir={"": "src"},
        ext_modules=[Extension("smoke._core", ["src/smoke/core.c"])],
    )
    EOF

    cat > "$out/src/smoke/__init__.py" <<'EOF'
    from ._core import answer
    EOF

    cat > "$out/src/smoke/core.c" <<'EOF'
    #include <Python.h>

    static PyObject *answer(PyObject *self, PyObject *args) {
      return PyLong_FromLong(42);
    }

    static PyMethodDef methods[] = {
        {"answer", answer, METH_NOARGS, "Return the smoke-test answer."},
        {NULL, NULL, 0, NULL},
    };

    static struct PyModuleDef module = {
        PyModuleDef_HEAD_INIT, "_core", NULL, -1, methods,
    };

    PyMODINIT_FUNC PyInit__core(void) {
      return PyModule_Create(&module);
    }
    EOF
  '';
in
  mkManylinuxWheel {
    inherit lib pkgs python src targetShell;
    pname = "mk-manylinux-wheel-smoke-${suffix}";
    version = "0.1.0";
    meta.description = "Smoke test for the mkManylinuxWheel API";
  }
