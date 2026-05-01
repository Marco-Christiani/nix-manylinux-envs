#define PY_SSIZE_T_CLEAN
#include <Python.h>

#include <chrono>
#include <condition_variable>
#include <fcntl.h>
#include <features.h>
#include <future>
#ifndef BASELINE_PROBE_NO_FILESYSTEM
#include <filesystem>
#endif
#include <memory>
#include <memory_resource>
#include <random>
#include <sstream>
#include <string>
#include <sys/stat.h>
#include <thread>
#include <unistd.h>
#include <variant>
#include <zlib.h>

#if defined(BASELINE_PROBE_ENABLE_FLOAT_CHARCONV)
#include <charconv>
#endif

#if defined(BASELINE_PROBE_ENABLE_GLIBC_239)
#include <stdbit.h>
#undef stdc_leading_zeros_ui
#endif

static void touch_newer_symbols(std::ostringstream &out) {
#ifdef __GLIBC_PREREQ
#if __GLIBC_PREREQ(2, 27)
  {
    loff_t in_off = 0;
    loff_t out_off = 0;
    (void)copy_file_range(-1, &in_off, -1, &out_off, 0, 0);
    out << " glibc_api=copy_file_range";
  }
#endif
#if __GLIBC_PREREQ(2, 28)
  {
    struct statx stx = {};
    (void)statx(AT_FDCWD, ".", AT_STATX_SYNC_AS_STAT, STATX_TYPE, &stx);
    out << " glibc_api=statx";
  }
#endif
#if __GLIBC_PREREQ(2, 34)
  {
    (void)close_range(3, 3, 0);
    out << " glibc_api=close_range";
  }
#endif
#if __GLIBC_PREREQ(2, 39)
#if defined(BASELINE_PROBE_ENABLE_GLIBC_239)
        {
          auto value = stdc_leading_zeros_ui(17u);
          out << " glibc_api=stdc_leading_zeros_ui:" << value;
        }
#endif
#endif
#endif
}

static void touch_stdlib_pressure(std::ostringstream &out) {
#if defined(BASELINE_PROBE_ENABLE_FLOAT_CHARCONV)
  {
    char buffer[64] = {};
    auto result =
        std::to_chars(buffer, buffer + sizeof(buffer), 3.141592653589793);
    if (result.ec == std::errc()) {
      out << " fchars=" << std::string(buffer, result.ptr);
    } else {
      out << " fchars=err";
    }
  }
#endif

#if defined(BASELINE_PROBE_ENABLE_PMR)
  {
    char storage[256] = {};
    std::pmr::monotonic_buffer_resource resource{storage, sizeof(storage)};
    std::pmr::string text{"pmr", &resource};
    text.append("-probe");
    out << " pmr=" << text;
  }
#endif

#if defined(BASELINE_PROBE_ENABLE_SHARED_STATE)
  {
    std::promise<int> promise;
    auto future = promise.get_future();
    std::mutex mutex;
    std::condition_variable condition;
    bool ready = false;

    std::thread worker([&] {
      {
        std::lock_guard<std::mutex> lock(mutex);
        ready = true;
      }
      condition.notify_one();
      promise.set_value(7);
    });

    {
      std::unique_lock<std::mutex> lock(mutex);
      condition.wait(lock, [&] { return ready; });
    }

    std::shared_ptr<int> value = std::make_shared<int>(future.get() + 35);
    out << " shared=" << *value;
    worker.join();
  }
#endif

#if defined(BASELINE_PROBE_ENABLE_VARIANT)
  {
    std::variant<int, std::string> payload = std::string("variant");
    out << " variant=" << std::get<std::string>(payload);
  }
#endif

#if defined(BASELINE_PROBE_ENABLE_RANDOM_DEVICE)
  {
    std::random_device entropy;
    out << " random=" << entropy();
  }
#endif
}

static PyObject *toolchain_probe(PyObject *, PyObject *) {
  std::ostringstream out;
  out << "__GLIBCXX__=" << __GLIBCXX__;
#ifdef __GNUC__
  out << " gcc=" << __GNUC__ << "." << __GNUC_MINOR__ << "."
      << __GNUC_PATCHLEVEL__;
#endif
#ifndef BASELINE_PROBE_NO_FILESYSTEM
  std::filesystem::path sample = "/tmp/../tmp/probe";
  out << " fs=" << sample.lexically_normal().string();
#else
  out << " fs=/tmp/probe";
#endif
  out << " zlib=" << zlibVersion();
  out << " zbound=" << compressBound(64);
  touch_newer_symbols(out);
  touch_stdlib_pressure(out);
  std::string text = out.str();
  return PyUnicode_FromStringAndSize(text.c_str(),
                                     static_cast<Py_ssize_t>(text.size()));
}

static PyMethodDef methods[] = {
    {"toolchain_probe", toolchain_probe, METH_NOARGS,
     "Return a tiny toolchain fingerprint."},
    {nullptr, nullptr, 0, nullptr},
};

static PyModuleDef module = {
    PyModuleDef_HEAD_INIT, "_core", nullptr, -1, methods,
};

PyMODINIT_FUNC PyInit__core(void) { return PyModule_Create(&module); }
