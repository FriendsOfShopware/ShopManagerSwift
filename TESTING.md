# Testing and CI

The pipeline builds shared test products once per platform family, runs cheap tests
early, and selects UI coverage conservatively. Full coverage has passed on
GitHub-hosted runners with two app builds and no test retries.

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

## Verified rollout

[Required run 34767309333](https://github.com/FriendsOfShopware/ShopManagerSwift/actions/runs/34767309333)
passed at `f770ecff291b10e1e1122a66501cf739ccb34e8f` on 13 September 2026.
Its conservative change selection expanded to the full suite on Xcode 27.0
build `27A5252f`.

| Measurement | Previous pipeline | Shared builds |
| --- | ---: | ---: |
| App builds | 24 | 2 |
| Jobs | 25 | 11 |
| Runner execution time | 282.9 minutes | 136.0 minutes |
| UI checks | 162 | 162 |
| UI executions, including repeats | 179 | 162 |
| App unit tests | 334, including duplicate iOS execution | 223: 112 macOS + 111 iOS |
| End-to-end elapsed time | 68.8 minutes | 70.4 minutes |

All 385 planned app tests passed on their first attempt, along with fast tests,
backend contracts, artifact transfers, and the final `verify / CI` gate. Both
compiled inventories were discovered on the first attempt. Runner work decreased
by 52%; this is not a billing estimate or an established elapsed-time speedup.
The new run overlapped manual release/minimum verification, and its longest job
queue was 34.9 minutes. Compare isolated, matching runs before drawing conclusions
about feedback time; ten runs are required before treating median/P95 as established.

[Focused release-toolchain run 34770481869](https://github.com/FriendsOfShopware/ShopManagerSwift/actions/runs/34770481869)
passed at `626d6920a7ecd0d77fb1270357e525db1b0ad73c`: three selected iPad product
tests and 111 iOS app unit tests, one shared iOS build, and no test retries.
This validates diagnostic selection and the product-input fixes; full regression
and minimum compatibility remain separate verification scopes.

The same product fixes also passed [three macOS release-toolchain UI checks and
112 unit tests](https://github.com/FriendsOfShopware/ShopManagerSwift/actions/runs/34772391834)
at `96a05af`, and the [iOS 26.0 product-creation regression plus 111 unit tests](https://github.com/FriendsOfShopware/ShopManagerSwift/actions/runs/34771715069)
at `e263c43`, each with one build and no retries. The manual macOS run completed
on `main` alongside automatic required verification, confirming that their
concurrency groups are independent. These focused runs do not authorize signing.

The [first attempt of follow-up required run 34772342556](https://github.com/FriendsOfShopware/ShopManagerSwift/actions/runs/34772342556/attempts/1)
at `96a05af` passed all 223 app unit tests and 161 of 162 UI checks. The remaining
iPad review-list test exceeded its five-minute limit after repeated 60-second
SpringBoard animation waits. The run stayed red; no automatic test retry occurred.
Its 54.9-minute elapsed time and 151.1 runner-minutes are a failed-run measurement,
not a successful benchmark. The [manual rerun](https://github.com/FriendsOfShopware/ShopManagerSwift/actions/runs/34772342556/attempts/2)
passed all 27 checks in that iPad worker and the final `verify / CI` gate without
rebuilding. The previously timed-out case passed in 43.4 seconds. This repeated
27 UI checks, bringing execution across both attempts to 412 app tests; the new
worker and gate added 23.6 runner-minutes. Total actual job execution was 174.7
runner-minutes, excluding inherited job records that GitHub copies into the new
attempt. The source was unchanged; this was a manual recovery, not a first-attempt
pass or a change to the automatic retry policy.

## Required checks

`tests.yml` calls `verify.yml`. Use **verify / CI** as the branch protection check.
It runs even for documentation changes and requires every planned job, worker,
and test to finish successfully. A cancelled job, missing report, skipped test,
empty discovery result, unknown test ID, or wrong commit cannot pass this check.
Manual and extended runs use distinct check names, so a manual smoke success
cannot satisfy the automatic branch-protection check.
Manual diagnostic runs use exact test and platform filters, and likewise cannot
satisfy branch protection or authorize a release.
Each manual dispatch has its own concurrency group, so diagnostics and benchmarks
on `main` cannot cancel an automatic required run or another manual run. New pushes
still cancel obsolete automatic checks for the same branch or pull request.

| Change or trigger | Fast tests | UI scope | Backend contracts |
| --- | --- | --- | --- |
| PR or main, module change | All API, domain, and app units | Smoke on macOS/iPhone/iPad plus affected modules | Request/payload/API changes |
| Shared, unknown, or CI change; missing comparison base | All | Full, currently 171 platform/test pairs | API/shared request changes; unknown changes always include contracts |
| Documentation only | CI syntax, ownership, localization, selector tests | Explicit skip | Explicit skip |
| Manual full / nightly regression | All | Full | Shopware 6.7 |
| Compatibility | All | Smoke, German, large text, accessibility, constrained layouts | Shopware 6.7 |
| Manual diagnostic | API/domain plus app units for selected platform families | Exact named UI tests on selected devices | Explicit skip |
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

Setup follows the same split: `ConnectViewModelTests` covers address parsing,
cancellation, authentication/access failures, draft preservation and persistence.
`SetupUITests` covers the shared first-shop flow, additional-shop cancellation,
password visibility, error recovery and German large-text/dark layouts on all
three platforms. Its transport is offline and its credentials never reach Keychain.
The happy path belongs to smoke; the German layout belongs to compatibility.
Run just this area with `-only-testing:shopwareUITests/SetupUITests` on the CI scheme.

`ShopwareDomain` now hosts production price parsing and linked-price logic. Its
headless tests cover incremental English/German input, invalid values, integer
bounds, linked/unlinked prices, and preservation of other currencies.

The separate `ShopwareContracts` package calls the production API over HTTP against
a disposable seeded Shopware service. It exercises first promotion-channel writes
and retained priority, German product-price persistence, and media-folder lifecycle.
It requires explicit localhost credentials and never silently skips if absent.
Supported backend pins are `v6.6.10.24` and `v6.7.14.0`; update them deliberately.
UI fixture transports remain deterministic and do not replace these contracts.

The product creation and currency-price form tests opt out of UIKit animations
in their Debug-only fixture. They check intermediate validation, failed saves,
and persisted values; they do not assess motion. This avoids simulator stalls
waiting for animation-completion notifications during numeric input. Other UI
cases retain animations, including navigation and adaptive-layout coverage.

## Retry and diagnostic policy

Assertion failures stay red. Only recognized simulator/test-runner startup errors
may retry once, in a fresh XCTest process. The retry selects only the failed test
IDs; a setup failure before any test may retry the selected worker once. Mixed
assertion/infrastructure failures are not retried. Both attempts remain visible.
There is no automatic quarantine and no whole-suite assertion retry. Artifact
transfers retry once independently, so a transient GitHub network failure does not
repeat successful tests; two failed transfers still fail the job and CI gate.
Toolchain and runtime preparation has its own 12-minute limit, so a simulator
that never finishes starting cannot consume the entire UI worker timeout.
A boot stalled for three minutes restarts only the newly created CI simulator
once, before any tests run. The restart is visible in the job warning and summary;
a second timeout fails preparation. This does not retry an executed test.

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
for its own SHA. Both verification outputs must equal the release SHA, and their scopes must be
full and compatibility respectively. Smoke and affected-area runs cannot sign. Signed
archives are separate builds on GitHub-hosted macOS runners; simulator artifacts
are never uploaded to TestFlight. TestFlight workflows queue across tags and manual
runs to avoid concurrent build-number allocation. The upload lanes query the latest
build across versions for each platform and override `CURRENT_PROJECT_VERSION` for
the app and widget together. The committed `MARKETING_VERSION` sets the release version.

## Commands

```sh
python3 .github/ci/static_checks.py
python3 -m unittest discover -s .github/ci -p 'test_*.py' -v
ruby fastlane/tests/testflight_versioning_test.rb
actionlint -shellcheck=
swift test --package-path Packages/ShopwareAdminAPI
swift test --package-path Packages/ShopwareDomain

# Inspect a selection locally without running it.
printf '["shopware/UI/Screens/ProductEditorSheet.swift"]' > /tmp/changed-paths.json
python3 .github/ci/planning.py --paths /tmp/changed-paths.json --output /tmp/plan.json

# Authoritative remote runs; these do not publish a release.
gh workflow run tests.yml -f mode=full
gh workflow run tests.yml -f mode=smoke
gh workflow run tests.yml -f mode=changed -f areas=products
gh workflow run tests.yml -f mode=full -f toolchain=release
gh workflow run tests.yml -f mode=diagnostic -f toolchain=release -f platforms=iPad \
  -f tests=ProductUITests/testCreateProductWithTaxAndPrice
gh workflow run tests.yml -f mode=diagnostic -f toolchain=minimum -f platforms=iPad \
  -f tests=ProductUITests/testCreateProductWithTaxAndPrice
gh workflow run nightly.yml -f suite=minimum
gh workflow run nightly.yml -f suite=canary
gh workflow run contracts.yml
```

Use diagnostic mode to verify a UI fix before spending another full matrix run.
It is available on required, release, minimum, and canary toolchains.
It still validates the complete compiled inventory, artifact provenance, selected
test results, and unit tests for each built platform family. An iPad-only selection
builds iOS once and runs one iPad worker; it does not build macOS. Unknown tests,
unsupported platforms, and filters on automatic/full/compatibility runs fail
planning. A successful diagnostic run is followed by the normal required checks.

## Measurements and review

`metrics.yml` records complete run timings after tests finish. Its reporting code
comes from the default branch and treats downloaded results as JSON data. It
records wall time, runner execution time, queue delay, phase/step times, app build
count, execution overhead, actual test counts, first-attempt failures, retries,
individual durations, toolchain/runner labels and artifact bytes. Metrics artifacts
last 90 days. Missing test evidence stays visible and never changes the CI gate.

`retryCount` counts retries inside an individual job. A manual GitHub job rerun is
a separate workflow attempt and can replace that job's compact report. Preserve
the original CI metrics artifact and failure diagnostics before rerunning; the
latest report alone cannot establish first-attempt success or total test executions
across manual attempts. GitHub also copies successful jobs into subsequent attempts
with new IDs and their original execution timestamps; aggregate job timing from
`filter=all` can therefore count inherited work twice. Exclude manually rerun
workflows from automated baseline comparisons and account for their newly executed
jobs separately. Use first-attempt full runs for the baseline comparison.

Download metrics artifacts into one directory and compare matching scope/count/
result/toolchain/area cohorts. Older metrics without toolchain metadata remain in
their own unknown-toolchain cohort:

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
