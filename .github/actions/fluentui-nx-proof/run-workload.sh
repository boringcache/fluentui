#!/usr/bin/env bash
set -euo pipefail

case "$WORKLOAD" in
  main)
    yarn nx run workspace-plugin:check-graph
    yarn nx g @fluentui/workspace-plugin:tsconfig-base-all --verify
    yarn nx g @fluentui/workspace-plugin:normalize-package-dependencies --verify

    # These packages generate files that Fluent UI does not declare as Nx
    # outputs. The v8 react and fluent2-theme build targets declare no outputs
    # at all, while the JSX runtime omits its generated package directories.
    # Rebuild them on each clean runner so the remote-cache comparison remains
    # conservative and correct without patching the upstream project graph.
    yarn nx run-many -t build \
      -p api-docs digest react-jsx-runtime react fluent2-theme \
      --skip-nx-cache
    test -f packages/react/lib/index.d.ts
    test -f packages/fluent2-theme/lib/index.d.ts
    test -f packages/react-components/react-jsx-runtime/jsx-runtime/package.json
    yarn tsc -p ./tsconfig.just-scripts-configs.json

    yarn check:installed-dependencies-versions
    yarn nx format:check --base "$NX_BASE"

    # Fluent UI's type-check targets consume package build outputs, but the Nx
    # graph does not consistently order those targets. Complete the affected
    # builds first so faster remote-cache restores cannot race type checking.
    yarn nx affected -t build --nxBail
    FLUENT_JEST_WORKER=2 yarn nx affected \
      -t test lint type-check test-ssr test-integration verify-packaging \
      --nxBail

    git status --porcelain
    git diff-index --quiet HEAD --
    ;;

  react-compiler-analyzer)
    yarn nx affected -t react-compiler-analyzer--lint --nxBail
    ;;

  react-major-versions-integration)
    # RIT also consumes the generated JSX-runtime package directories, which
    # are absent from Fluent UI's declared Nx outputs.
    yarn nx run react-jsx-runtime:build --skip-nx-cache
    test -f packages/react-components/react-jsx-runtime/jsx-runtime/package.json

    yarn rit --react 17 --install-deps
    yarn rit --react 18 --install-deps

    "$GITHUB_WORKSPACE"/source/tmp/rit/react-17/node_modules/.bin/cypress verify
    "$GITHUB_WORKSPACE"/source/tmp/rit/react-18/node_modules/.bin/cypress verify

    yarn nx affected \
      -t test-rit--17--e2e,test-rit--18--e2e \
      --exclude='react-19-tests-v9,react-charting,react'

    NODE_OPTIONS=--max-old-space-size=4096 \
      FLUENT_JEST_WORKER=2 \
      yarn nx affected \
        -t test-rit--17--type-check,test-rit--18--type-check,test-rit--17--test,test-rit--18--test \
        --exclude='react-19-tests-v9'
    ;;

  e2e)
    yarn playwright install --with-deps
    yarn cypress verify
    yarn nx affected -t e2e --nxBail --parallel 1
    ;;

  *)
    echo "Unknown workload: $WORKLOAD" >&2
    exit 2
    ;;
esac
