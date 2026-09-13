# Testing and CI

The pipeline builds shared test products once per platform, runs cheap tests early,
and selects UI coverage conservatively. The first rollout is being verified on
GitHub-hosted runners; the measurements below are the previous pipeline's baseline.

## Measured baseline

Measured on 13 September 2026 using commit `4b604989e7680405fdf393e75539058bd05ffa2c`
and [successful run 34714302976](https://github.com/FriendsOfShopware/ShopManagerSwift/actions/runs/34714302976).

| Measurement | Observed result |
| --- | --- |
| End-to-end workflow time | 68.8 minutes |
| Sum of job execution time | 282.9 runner-minutes, excluding queue time; not a billing estimate |
| Job count | 25: API plus 8 areas on 3 platforms |
| Peak simultaneous jobs | 5 observed; this is not a verified account-wide quota |
| App build invocations | 24 independent `xcodebuild test` jobs with fresh DerivedData |
| App unit execution | 112 tests on macOS in 2.9 seconds; 111 tests on each iOS device in 1.8–2.2 seconds |
| iOS unit job time | 8.4 minutes on iPad; 8.8 minutes on iPhone |
| API job | About 36 seconds of execution, starting 11.1 minutes after the workflow was created |
| UI coverage | 162 distinct test/platform combinations across 7 areas |
| UI attempts | 179; two failing cases caused their suites to repeat, adding 17 executions |
| Time before first UI test | 113 runner-minutes in aggregate, including build, installation, and test startup |

## Required checks

`tests.yml` calls `verify.yml`. Use **verify / CI** as the branch protection check.
It runs even for documentation changes and requires every planned job, worker,
and test to finish successfully. A cancelled job, missing report, skipped test,
empty discovery result, unknown test ID, or wrong commit cannot pass this check.

| Change or trigger | Fast tests | UI scope | Backend contracts |
| --- | --- | --- | --- |
| PR or main, module change | All API, domain, and app units | Smoke on macOS/iPhone/iPad plus affected modules | Request/payload/API changes |
| Shared, unknown, or CI change; missing comparison base | All | Full, currently 162 platform/test pairs | API/shared request changes; unknown changes always include contracts |
| Documentation only | CI syntax, ownership, localization, selector tests | Explicit skip | Explicit skip |
| Manual full / nightly regression | All | Full | Shopware 6.7 |
| Compatibility | All | Smoke, German, large text, accessibility, constrained layouts | Shopware 6.7 |
| Scheduled backend matrix | — | — | Shopware 6.6 and 6.7 |
| TestFlight | All at exact release SHA | Full on release toolchain, then minimum compatibility | Required before signing/upload |

PR selection compares against the merge base. Automatic main runs compare against
the most recent successfully validated **automatic main push** that is an ancestor
of HEAD. A manual smoke run never advances that baseline. Missing history or API
access expands to full coverage. Renames include both paths.

## Builds and workers

The shared `CI` scheme declares native `Unit`, `UISmoke`, `UIRegression`, and
`UICompatibility` test plans. Existing module schemes remain useful locally.
The shared `UIRegression` build contains all app units and the complete assigned UI
suite. Selection happens during execution, without rebuilding.

- One ARM64 macOS build and one ARM64 iOS Simulator build per toolchain and commit.
- Each build discovers the actual compiled tests and checks them against the manifest.
- App unit tests run once on macOS and once on iOS using these products.
- UI workers reuse a tarred `.xctestproducts` artifact. iPhone and iPad use the same iOS artifact.
- At most five UI workers: one macOS, up to two iPhone, up to two iPad. Test duration
  estimates balance workers; UI execution stays serial inside each worker.
- Products include exact SHA, Xcode build, SDK version/build, architecture and
  configuration. Consumers check metadata and archive SHA256 before execution.
- API and portable domain tests run on Linux with Swift 6.2, outside the Mac queue.

GitHub artifacts transfer commit-specific binaries; caches hold dependencies and
portable package incremental builds. No stale DerivedData cache stands in for a
build. The app currently has only local package dependencies, so it needs no remote
SourcePackages cache. The minimum iOS runtime download has a separate versioned cache.

`toolchains.json` declares the required Xcode build, minimum compatibility toolchain,
release toolchain, and newest-image canary. Required/release/minimum builds fail if
the declared Xcode build is absent; refresh pins through reviewed changes. The
canary follows the image default so a new Xcode can be evaluated before promotion.

Minimum compatibility uses iOS **26.0** explicitly, downloading the runtime when
needed; it never silently substitutes 26.2. Hosted macOS compatibility uses the
available macOS 26 image (currently 26.6.2), not a claim that macOS 26.0 itself was
executed. Current required testing uses macOS/iOS 27. Distribution archives use
stable Xcode 26.6 and get full checks on that same toolchain before signing.

## Adding a module or test

1. Add the source and tests normally. Give each UI test class its own Swift file.
2. Add ownership patterns and shared dependencies to `.github/ci/areas.json`.
3. Assign each UI test method, supported platforms, smoke and compatibility flags.
   Unassigned or stale methods fail both source validation and compiled discovery.
4. Update the corresponding native plan when introducing a class or changing smoke/
   compatibility membership. The static checker rejects mismatches.
5. Run the selector checks and the local module scheme. Do not add another CI job
   for the module; the planner assigns its tests to existing workers.

Use parameterized domain/model tests for validation, parsing, calculations,
permissions and payload preservation. Keep UI coverage for keyboard input, focus,
navigation, sheets, selection, accessibility and representative save/error recovery.
`ShopwareDomain` now hosts production price parsing and linked-price logic. Its
headless tests cover incremental English/German input, invalid values, integer
bounds, linked/unlinked prices, and preservation of other currencies.

The separate `ShopwareContracts` package calls the production API over HTTP against
a disposable seeded Shopware service. It exercises first promotion-channel writes
and retained priority, German product-price persistence, and media-folder lifecycle.
It requires explicit localhost credentials and never silently skips if absent.
Supported backend pins are `v6.6.10.24` and `v6.7.14.0`; update them deliberately.
UI fixture transports remain deterministic and do not replace these contracts.

## Retry and diagnostic policy

Assertion failures stay red. Only recognized simulator/test-runner startup errors
may retry once, in a fresh XCTest process. The retry selects only the failed test
IDs; a setup failure before any test may retry the selected worker once. Mixed
assertion/infrastructure failures are not retried. Both attempts remain visible.
There is no automatic quarantine and no whole-suite assertion retry.

Each report checks exact selected versus executed IDs and the final xcodebuild exit
status. First-attempt failures, retries, runtime warnings and test durations are
retained. Successful routine runs upload compact JSON/logs for 14 days. Failed,
retried and explicit visual runs also upload xcresult bundles and screenshots for
14 days. Shared products expire after one day. Nightly regression is a visual run.

## Scheduling and release

`nightly.yml` runs off hours at 00:17 UTC: full regression, minimum compatibility,
newest-toolchain canary, then the backend version matrix. These suites run in
sequence and cap UI concurrency at two to limit competition with PRs. This does
not reserve runner slots or guarantee priority over another workflow.

`testflight.yml` requires full release-toolchain checks and minimum compatibility
for its own SHA. Both verification outputs must equal the release SHA. Signed
archives are separate builds on GitHub-hosted macOS runners; simulator artifacts
are never uploaded to TestFlight. Manual/tag publication behavior is unchanged.

## Commands

```sh
python3 .github/ci/static_checks.py
python3 -m unittest discover -s .github/ci -p 'test_*.py' -v
actionlint -shellcheck=
swift test --package-path Packages/ShopwareAdminAPI
swift test --package-path Packages/ShopwareDomain

# Inspect a selection locally without running it.
printf '["shopware/UI/Screens/ProductEditorSheet.swift"]' > /tmp/changed-paths.json
python3 .github/ci/planning.py --paths /tmp/changed-paths.json --output /tmp/plan.json

# Authoritative remote runs; these do not publish a release.
gh workflow run tests.yml -f mode=full
gh workflow run tests.yml -f mode=smoke
gh workflow run tests.yml -f mode=full -f toolchain=release
gh workflow run nightly.yml -f suite=minimum
gh workflow run nightly.yml -f suite=canary
gh workflow run contracts.yml
```

## Measurements and review

`metrics.yml` records complete run timings after tests finish. Its reporting code
comes from the default branch and treats downloaded results as JSON data. It
records wall time, runner execution time, queue delay, phase/step times, app build
count, execution overhead, actual test counts, first-attempt failures, retries,
individual durations, toolchain/runner labels and artifact bytes. Metrics artifacts
last 90 days. Missing test evidence stays visible and never changes the CI gate.

Download metrics artifacts into one directory and compare matching scope/count/
result cohorts:

```sh
python3 .github/ci/metrics.py --compare /tmp/ci-metrics
# Update estimates from a successful full run after downloading its compact evidence:
GITHUB_REPOSITORY=FriendsOfShopware/ShopManagerSwift python3 .github/ci/metrics.py \
  --run-id RUN_ID --evidence /tmp/evidence --update-durations /tmp/durations.json
```

Review the candidate duration file before replacing `.github/ci/durations.json`.
Compare at least ten representative runs before treating median/P95 feedback time
as established. Compare full runs with full runs, and affected-area runs separately.
The baseline is 68.8 minutes wall and 282.9 runner-minutes. The initial acceptance
criterion is full 162-pair coverage with two app builds instead of 24; a green
subset or successful retry alone is not full-matrix verification.
