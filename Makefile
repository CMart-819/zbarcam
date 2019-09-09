VENV_NAME=venv
PIP=$(VENV_NAME)/bin/pip
TOX=`which tox`
GARDEN=$(VENV_NAME)/bin/garden
PYTHON=$(VENV_NAME)/bin/python
ISORT=$(VENV_NAME)/bin/isort
FLAKE8=$(VENV_NAME)/bin/flake8
TWINE=`which twine`
SOURCES=src/ tests/ setup.py setup_meta.py
# using full path so it can be used outside the root dir
SPHINXBUILD=$(shell realpath venv/bin/sphinx-build)
DOCS_DIR=doc
SYSTEM_DEPENDENCIES= \
	build-essential \
	cmake \
	curl \
	libpython$(PYTHON_VERSION)-dev \
	libsdl2-dev \
	libzbar-dev \
	tox \
	virtualenv \
	wget
OS=$(shell lsb_release -si)
PYTHON_MAJOR_VERSION=3
PYTHON_MINOR_VERSION=6
PYTHON_VERSION=$(PYTHON_MAJOR_VERSION).$(PYTHON_MINOR_VERSION)
PYTHON_WITH_VERSION=python$(PYTHON_VERSION)
# python3 has a "m" suffix for both include path and library
PYTHON_M=$(PYTHON_WITH_VERSION)
SITE_PACKAGES_DIR=$(VENV_NAME)/lib/$(PYTHON_WITH_VERSION)/site-packages
TMPDIR ?= /tmp
DOWNLOAD_DIR = $(TMPDIR)/downloads
OPENCV_VERSION=4.0.1
OPENCV_BASENAME=opencv-$(OPENCV_VERSION)
OPENCV_ARCHIVE=$(OPENCV_BASENAME).tar.gz
OPENCV_ARCHIVE_PATH=$(DOWNLOAD_DIR)/$(OPENCV_ARCHIVE)
OPENCV_EXTRACT_PATH=$(DOWNLOAD_DIR)/$(OPENCV_BASENAME)
OPENCV_BUILD_LIB_DIR=$(OPENCV_EXTRACT_PATH)/build/lib
OPENCV_BUILD=$(OPENCV_BUILD_LIB_DIR)/python$(PYTHON_MAJOR_VERSION)/cv2*.so
OPENCV_DEPLOY=$(SITE_PACKAGES_DIR)/cv2*.so
NPROC=`grep -c '^processor' /proc/cpuinfo`


ifeq ($(PYTHON_MAJOR_VERSION), 3)
	PYTHON_M := $(PYTHON_M)m
endif


all: system_dependencies virtualenv opencv

venv:
	test -d venv || virtualenv -p python$(PYTHON_MAJOR_VERSION) venv

virtualenv: venv
	$(PIP) install Cython==0.28.6
	$(PIP) install -r requirements/requirements.txt
	$(GARDEN) install xcamera

system_dependencies:
ifeq ($(OS), Ubuntu)
	sudo apt install --yes --no-install-recommends $(SYSTEM_DEPENDENCIES)
endif

$(OPENCV_ARCHIVE_PATH):
	mkdir -p $(DOWNLOAD_DIR)
	curl --location https://github.com/opencv/opencv/archive/$(OPENCV_VERSION).tar.gz \
		--progress-bar --output $(OPENCV_ARCHIVE_PATH)

# The build also relies on virtualenv, because we make references to it.
# Plus numpy is required to build OpenCV Python module.
$(OPENCV_BUILD): $(OPENCV_ARCHIVE_PATH) virtualenv
	tar -xf $(OPENCV_ARCHIVE_PATH) --directory $(DOWNLOAD_DIR)
	cmake \
		-D CMAKE_SHARED_LINKER_FLAGS=-l$(PYTHON_M) \
		-D BUILD_SHARED_LIBS=ON \
		-D BUILD_STATIC_LIBS=OFF \
		-D BUILD_DOCS=OFF \
		-D BUILD_OPENCV_APPS=OFF \
		-D BUILD_OPENCV_JAVA=OFF \
		-D BUILD_OPENCV_JAVA_BINDINGS_GENERATOR=OFF \
		-D BUILD_OPENCV_NONFREE=OFF \
		-D BUILD_OPENCV_PYTHON2=OFF \
		-D BUILD_OPENCV_PYTHON3=ON \
		-D BUILD_OPENCV_STITCHING=OFF \
		-D BUILD_OPENCV_SUPERRES=OFF \
		-D BUILD_OPENCV_TS=OFF \
		-D BUILD_PACKAGE=OFF \
		-D BUILD_PERF_TESTS=OFF \
		-D BUILD_TESTS=OFF \
		-D BUILD_WITH_DEBUG_INFO=OFF \
		-D OPENCV_SKIP_PYTHON_LOADER=ON \
		-D OPENCV_PYTHON$(PYTHON_MAJOR_VERSION)_INSTALL_PATH=$(SITE_PACKAGES_DIR) \
		-D PYTHON$(PYTHON_MAJOR_VERSION)_PACKAGES_PATH=$(SITE_PACKAGES_DIR) \
		-D PYTHON$(PYTHON_MAJOR_VERSION)_EXECUTABLE=$(PYTHON) \
		-D PYTHON$(PYTHON_MAJOR_VERSION)_INCLUDE_PATH=/usr/include/$(PYTHON_M)/ \
		-D PYTHON$(PYTHON_MAJOR_VERSION)_LIBRARIES=/usr/lib/x86_64-linux-gnu/lib$(PYTHON_M).so \
		-D PYTHON_DEFAULT_EXECUTABLE=/usr/bin/python$(PYTHON_MAJOR_VERSION) \
		-D WITH_1394=OFF \
		-D WITH_CUDA=OFF \
		-D WITH_CUFFT=OFF \
		-D WITH_GIGEAPI=OFF \
		-D WITH_GTK=OFF \
		-D WITH_JASPER=OFF \
		-D WITH_OPENEXR=OFF \
		-D WITH_PVAPI=OFF \
		-B$(OPENCV_EXTRACT_PATH)/build -H$(OPENCV_EXTRACT_PATH)
	cmake --build $(OPENCV_EXTRACT_PATH)/build -- -j$(NPROC)

$(OPENCV_DEPLOY): $(OPENCV_BUILD) virtualenv
	cp $(OPENCV_BUILD) $(SITE_PACKAGES_DIR)

opencv: $(OPENCV_DEPLOY)

run/linux: virtualenv
	$(PYTHON) src/main.py

run: run/linux

test:
	$(TOX)

uitest: virtualenv
	$(PIP) install -r requirements/test_requirements.txt
	PYTHONPATH=src $(PYTHON) -m unittest discover --top-level-directory=. --start-directory=tests/ui/

isort-check: virtualenv
	$(ISORT) --check-only --recursive --diff $(SOURCES)

isort-fix: virtualenv
	$(ISORT) --recursive $(SOURCES)

flake8: virtualenv
	$(FLAKE8) $(SOURCES)

lint: isort-check flake8

docs/clean:
	rm -rf $(DOCS_DIR)/build/

docs:
	cd $(DOCS_DIR) && SPHINXBUILD=$(SPHINXBUILD) make html

release/clean:
	rm -rf dist/ build/

release/build: release/clean
	$(PYTHON) setup.py sdist bdist_wheel
	$(PYTHON) setup_meta.py sdist bdist_wheel
	$(TWINE) check dist/*

release/upload:
	$(TWINE) upload dist/*

clean: release/clean docs/clean
	py3clean src/
	find src/ -type d -name "__pycache__" -exec rm -r {} +
	find src/ -type d -name "*.egg-info" -exec rm -r {} +

clean/full: clean
	rm -rf $(VENV_NAME) .tox/ $(DOWNLOAD_DIR)
