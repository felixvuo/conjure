
SHELL := /bin/bash

# these are default values
# override by calling the makefile like so: "GHC_VERSION=8.6 make"
export GHC_VERSION?=8.6
export BIN_DIR?=${HOME}/.local/bin
export CI?=false
export BUILD_TESTS?=false
export COVERAGE?=false
export LIMIT_TIME?=10

.PHONY: install
install:
	@echo "Using GHC version ${GHC_VERSION} (major version)"
	@echo "Set the environment variable GHC_VERSION to change this location."
	@echo "For example: \"GHC_VERSION=8.4 make install\""
	@echo "Supported versions: 8.0, 8.2, 8.4, 8.6"
	@echo ""
	@echo "Installing executables to ${BIN_DIR}"
	@echo "Add this directory to your PATH."
	@echo "Set the environment variable BIN_DIR to change this location"
	@echo "For example: \"BIN_DIR=your/preferred/path make install\""
	@echo ""
	@mkdir -p ${BIN_DIR}
	@echo Using Stack file: etc/hs-deps/stack-${GHC_VERSION}.yaml
	@if ${BUILD_TESTS} ; then echo "BUILD_TESTS=true"; fi
	@if ${CI} ; then echo "CI=true"; fi
	@bash etc/build/install-stack.sh
	@cp etc/hs-deps/stack-${GHC_VERSION}.yaml stack.yaml
	@if  [ ${GHC_VERSION} == "head" ] ; then\
		stack --local-bin-path ${BIN_DIR} setup --resolver nightly;\
	else\
		stack --local-bin-path ${BIN_DIR} setup;\
	fi
	@bash etc/build/version.sh
	@stack runhaskell etc/build/gen_Operator.hs
	@stack runhaskell etc/build/gen_Expression.hs
	@bash etc/build/install.sh
	@etc/build/copy-conjure-branch.sh
	@cp -r etc/savilerow/* ${BIN_DIR}
	@echo - savilerow
	@echo
	@${BIN_DIR}/conjure --version
	@${BIN_DIR}/savilerow -help | head -n1

.PHONY: test
test:
	@if ${COVERAGE}; then \
		stack test --coverage --test-arguments '--limit-time ${LIMIT_TIME}';\
		stack hpc report conjure-cp $(find . -name conjure.tix);\
		ls .stack-work/install/*/*/*/hpc/combined/custom;\
	else\
		stack test --test-arguments '--limit-time ${LIMIT_TIME}';\
	fi

.PHONY: preinstall
preinstall:
	@bash etc/build/version.sh
	@stack runhaskell etc/build/gen_Operator.hs
	@stack runhaskell etc/build/gen_Expression.hs

.PHONY: freeze
freeze:
	@bash etc/build/freeze-deps.sh

.PHONY: refreeze
refreeze:
	@make clean
	@BUILD_TESTS=yes make install-using-cabal
	@make freeze

.PHONY: clean
clean:
	@bash etc/build/clean.sh

.PHONY: docs
docs:
	(cd docs; make conjure-help; make latexpdf; make singlehtml)

.PHONY: ghci
ghci:
	@cabal exec ghci -- -isrc -isrc/test           \
	    -idist/build/autogen                       \
	    -XFlexibleContexts                         \
	    -XFlexibleInstances                        \
	    -XMultiParamTypeClasses                    \
	    -XNoImplicitPrelude                        \
	    -XOverloadedStrings                        \
	    -XQuasiQuotes                              \
	    -XScopedTypeVariables                      \
	    -XTypeOperators                            \
	    -XLambdaCase                               \
	    -XMultiWayIf                               \
	    -fwarn-incomplete-patterns                 \
	    -fwarn-incomplete-uni-patterns             \
	    -fwarn-missing-signatures                  \
	    -fwarn-name-shadowing                      \
	    -fwarn-orphans                             \
	    -fwarn-overlapping-patterns                \
	    -fwarn-tabs                                \
	    -fwarn-unused-do-bind                      \
	    -fwarn-unused-matches                      \
	    -Wall                                      \
	    -Werror                                    \
	    `find src -name '*.hs' | grep -v 'Main.hs' | grep -v '\.#'`

.PHONY: hlint
hlint:
	-@hlint -r `find src -name '*.hs' | grep -v LogFollow` \
	    -i "Use camelCase" \
	    -i "Reduce duplication" \
	    -i "Use &&" \
	    -i "Use ++" \
	    -i "Redundant return" \
	    -i "Monad law, left identity"

# @etc/build/silent-wrapper.sh etc/build/install-glasgow-subgraph-solver.sh

.PHONY: solvers
solvers:
	@echo "Installing executables to ${BIN_DIR}"
	@echo "Add this directory to your PATH."
	@echo "Set the environment variable BIN_DIR to change this location."
	@echo "For example: \"BIN_DIR=your/preferred/path make install\""
	@echo ""
	@echo "Dependencies: cmake and gmp."
	@if [ `uname` == "Darwin" ]; then echo "You can run: 'brew install cmake gmp' to install them."; fi
	@echo ""
	@mkdir -p ${BIN_DIR}
	@etc/build/silent-wrapper.sh etc/build/install-bc_minisat_all.sh
	@etc/build/silent-wrapper.sh etc/build/install-boolector.sh
	@etc/build/silent-wrapper.sh etc/build/install-cadical.sh
	@etc/build/silent-wrapper.sh etc/build/install-kissat.sh
	@etc/build/silent-wrapper.sh etc/build/install-chuffed.sh
	@etc/build/silent-wrapper.sh etc/build/install-gecode.sh
	@etc/build/silent-wrapper.sh etc/build/install-glucose.sh
	@etc/build/silent-wrapper.sh etc/build/install-lingeling.sh
	@etc/build/silent-wrapper.sh etc/build/install-minion.sh
	@etc/build/silent-wrapper.sh etc/build/install-nbc_minisat_all.sh
	@etc/build/silent-wrapper.sh etc/build/install-open-wbo.sh
	@etc/build/silent-wrapper.sh etc/build/install-yices.sh
	@etc/build/silent-wrapper.sh etc/build/install-z3.sh
