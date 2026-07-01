I have enough context to produce the plan. Let me write it directly.

# Shopware Apple Port — Parity Plan vs. Android

## 1. Executive summary

The Apple port has reached strong functional parity on the core CRUD/browse flows (orders, customers, products, media, reviews, promotions listings + detail + edit) and the API/data-client infrastructure is a near-1:1 port. Parity gaps cluster into three themes: (a) **unwired backends** — Orders/Customers detail screens where the VM/repo/model plumbing exists but the UI never surfaces or drives it (internal note, tracking edit, quick actions, customer stats); (b) **two whole unported subsystems** — the live Analytics/Reports engine (12 KPIs, date-range + 6-dimension filtering, breakdowns, prior-period deltas) and the WidgetKit extension target; and (c) **the push stack**, which is an intentional architectural divergence (local BGAppRefreshTask polling instead of server FCM) where only deep-linking and per-shop UI are genuinely portable. The highest ROI is the cluster of small detail-screen wirings (mostly S effort against already-wired backends), followed by the Products linked-price/EAN work and the L-effort Analytics engine.

## 2. Gaps by module

### Orders — mostly dead-wired backends, low effort
| Gap | Sev | Eff | Pointer |
|---|---|---|---|
| Internal note add/edit/save | major | M | Add note card to `OrderDetailView.swift` (sections 37-43); drive existing `OrderDetailViewModel.setInternalComment` → `AppRepository.setInternalComment`; bind `detail.internalComment` (OrderModels.swift:75). |
| Tracking code add/remove editing | major | M | Replace read-only `LabeledContent("Tracking")` (OrderDetailView.swift:175-177) with per-code remove + TextField/Add; call existing `vm.setTrackingCodes`. |
| Customer note (customerComment) display | moderate | S | Render `detail.customerComment` (OrderModels.swift:74, already parsed) as a tinted card in customer section. |
| Customer email/call quick actions | moderate | S | In `headerSection` (OrderDetailView.swift:85-87) wrap email in `Link(mailto:)`; render `detail.phone` (OrderModels.swift:73) as `Link(tel:)`. |
| Net total line | minor | S | Add `detail.netTotal` (OrderModels.swift:65) row to `totalsSection` (OrderDetailView.swift:137-151); add "Net" xcstring. |
| Open/View document (QuickLook) | minor | S | Add `.quickLookPreview` alongside ShareLink in documentsSection (OrderDetailView.swift:190-211). |
| Generate-document confirm dialog | minor | S | Wrap `vm.generateDocument` menu action (OrderDetailView.swift:203-209) in `.confirmationDialog`; add confirm xcstrings. |
| Line-item product number subtitle | minor | S | Add `item.productNumber` (OrderModels.swift:12) to lineItemsSection caption (OrderDetailView.swift:119-133). |

### Customers — presentation-layer gaps over fetched-but-unused fields
| Gap | Sev | Eff | Pointer |
|---|---|---|---|
| Paginated order history + total + load-more | moderate | M | Rewire `CustomerDetailViewModel.loadOrders` (CustomerDetailView.swift:34-42) from flat `.setLimit(20)` to generic `ListingState<T>` (ListingState.swift) with total header, load-more, error retry. |
| Summary tiles (count / top spender / repeat buyers) | moderate | S | Use `ListingScaffold` header slot in `CustomersView.swift:47-51`; render `ShopSnapshot.topCustomers` (Models.swift:176/244) as 3 StatTiles. |
| Email/Call quick actions in detail header | moderate | S | `CustomerDetailView.swift:90-93`: `Link(mailto:)` + render `detail.phone` (CustomerQueries.swift:42) as `Link(tel:)`. |
| "Last order" stat (relative time) | minor | S | Add MetricRow using `detail.lastOrderMs` (CustomerModels.swift:22) + `relativeAgoText` (RelativeTime.swift) at CustomerDetailView.swift:111-114. |
| "Customer since" in header subtitle | minor | S | Render `detail.customerSince` (CustomerModels.swift:23) in header (CustomerDetailView.swift:88-109); add "Since" xcstring. |

### Products + Media
| Gap | Sev | Eff | Pointer |
|---|---|---|---|
| Linked gross/net price editor (sw-price-field) | major | M | Build PriceEditState/PriceEditor (gross+net TextFields + link lock, tax recompute) for `ProductEditSheet`/`VariantEditSheet` (ProductDetailView.swift:262-273,329-340) + `ProductActionSheet.swift:66-77`; extend `saveProductDetail/saveVariantEdit/saveProductQuickEdit` (ProductQueries.swift) to write gross+net+linked verbatim instead of `scaledPrice` (QuerySupport.swift:50-63). |
| EAN + manufacturer number view/edit | major | M | Add `ean`/`manufacturerNumber` to `ProductDetail` (ProductModels.swift); add to fetch includes + patch in `saveProductDetail` (ProductQueries.swift:84-92,169-186); add identifiers section + edit inputs to ProductDetailView. |
| Per-shop ProductFieldConfig gating | moderate | M | Add `ProductFieldConfig` + `productFields` to `ConnectedShop` (Models.swift:64-138); gate ProductDetailView sections/edit fields. (Also spans Shop Settings — see below.) |
| Camera capture for photo upload | moderate | M | Add camera source (VisionKit/UIImagePickerController) beside `PhotosPicker` in `ProductActionSheet.swift:80` and `MediaView.swift:124-128`. |
| Media library search | moderate | S | Add `.searchable` → `criteria.setTerm` in MediaViewModel.load (MediaView.swift:45-59); `MediaQueries.swift:13-21`. |
| Media pagination / infinite scroll | moderate | M | Migrate bespoke `MediaViewModel` to `ListingState` + ListingScaffold loadMore, or add manual paging past `setLimit(50)`. |
| Variant tax rate for net/price math | minor | S | Add `addAssociation("tax")` + taxRate/netPrice/priceLinked to `fetchProductVariants`/`ProductVariant` (ProductQueries.swift:134-163, ProductModels.swift:58-68). Prereq for linked variant editor. |

### Reviews + Promotions
| Gap | Sev | Eff | Pointer |
|---|---|---|---|
| Generate-codes dialog (amount input + 1..500 validation + result feedback) | major | M | Replace hardcoded `amount: 10` in `PromosView.swift:57-62`; add amount TextField sheet, validation, busy state, pluralized success/failure. API already supports variable amount (`AppRepository.addPromotionCodes`). |
| Active toggle reload + snapshot refresh + error surfacing | moderate | S | `PromosView.swift:51-56`: replace local `mutateItem` with `listing.reload()` (re-runs `parsePromo` so status/window recompute) + `model.refresh`; surface errors instead of `try?`. |
| Promo schedule/window line in card | moderate | S | Render already-computed `promo.window` (Models.swift:187) in PromoCard subtitle (PromosView.swift:108-116). |
| Promo hero summary header | moderate | M | Pass snapshot into `PromosView` (MoreView.swift:48); add ListingScaffold header with live-campaign count + summed active redemptions. |
| Distinct Keep-hidden vs Reject + per-review status badge | minor | S | Status-conditional swipe actions + `StatusBadge` (Components.swift:30) on ReviewCard (ReviewInboxView.swift:79-90,135-163). |
| Action-error surfacing + snapshot refresh on approve/reject | minor | S | ReviewInboxView.setStatus (114-130): surface error, call `AppRepository.refresh` after success. |

### Home + Reports + Analytics — the dominant unported product
Home dashboard itself is at parity. Reports is a thin snapshot re-render.
| Gap | Sev | Eff | Pointer |
|---|---|---|---|
| Live Analytics engine (12 KPIs, ViewModel, queries) | major | L | New `AnalyticsQueries.swift` (Criteria.terms/histogram/sum already in Packages), `KpiType` enum, `ReportsViewModel`, KPI card types w/ per-card loading/error/retry. |
| Date-range filter bar (Today/7/30/90) | major | M | Range presets driving `rangeFor(preset)` + histogram interval-by-span; re-fetch KPIs. (DateRangeEditor in FilterSheet.swift:274-290 is listing-only — new analytics surface needed.) |
| Multi-select filter sheet (6 dimensions) | major | L | AnalyticsFilterSheet + `fetchAnalyticsFilterOptions` (salesChannel/orderState/paymentState/deliveryState/customerGroup/country) applied to every order-based KPI, debounced reload, active-filter chip. |
| Trend cards w/ per-KPI chart + prior-period delta | major | L | Per-KPI charts (OrderCount/AOV/NewCustomers) + true `f.previous()` window; replace faked first-3-vs-last-3 delta in ReportsView.swift:27-47. |
| Breakdown (top-N) cards for 7 dimensions | major | L | RankBar breakdown cards for salesChannel/payment/shipping/country/manufacturer/promotion (only topProducts exists). |
| Cross-shop comparison period-aware + ranked bars | moderate | M | Replace fixed `todayRevenue` (ReportsView.swift:66-81) with per-shop range revenue query + RankBars. |
| CustomerCount single-number KPI (cumulative + delta) | moderate | S | SingleNumberCard counting customers created-before-window-end vs previous window. |

### Push + Background Sync + Notifications
Architectural divergence (local polling vs FCM). Most push claims are N/A by design; portable gaps only:
| Gap | Sev | Eff | Pointer |
|---|---|---|---|
| Server-driven push (APNs) | major | L | **Deferred** — see out-of-scope. Requires aps-environment entitlement + remote-notification bg mode. |
| Push token registration (ce_fcn /sync upsert) | major | L | **Deferred with APNs.** Needs `EntityRepository.upsert`/`ShopwareClient.sync` (below) + PushQueries + AppRepository push facade. |
| Per-shop push status UI + register/unregister | moderate | M | **Deferred with APNs** (ShopSettingsView + PushStatus type). |
| Notification tap deep-link (open order / select shop) | moderate | M | **Portable now**: add `UNUserNotificationCenterDelegate` (didReceive), attach orderId to `SyncService.post` userInfo (SyncService.swift), wire to `AppViewModel.selectShop` + order navigationDestination. Works for existing local notifications. |
| Per-shop contextual notification permission prompt | minor | S | Lower priority; current global prompt on sync-enable (AppViewModel.swift:100) is acceptable. |

### Connect / Onboarding / Shop settings / Nav shell / Widgets
| Gap | Sev | Eff | Pointer |
|---|---|---|---|
| WidgetKit extension target | major | L | Add app-extension target (project.pbxproj has only 3 targets); wrap existing `WidgetViews.swift` in `Widget`/`TimelineProvider`/`WidgetBundle`; read shared cache via `WidgetData.swift` + App Group `group.com.shopware.shopware` (already wired). |
| Per-shop product-field config in Shop Settings | moderate | M | Same ProductFieldConfig work as Products module; add toggles section to `ShopSettingsView.swift`. |
| Manage-shops inline add + empty-state | minor | S | Add bottom "Add shop" button + ContentUnavailableView empty-state to `ManageShopsView.swift` (capability exists elsewhere but not on this screen). |

### API client / data-layer infrastructure
| Gap | Sev | Eff | Pointer |
|---|---|---|---|
| Analytics KPI query layer (AnalyticsQueries + repo facade) | major | L | Backs the Reports engine — `loadKpi`/`loadShopRevenue`/`analyticsFilterOptions` on AppRepository. Build with the Analytics engine. |
| Push registration data layer (PushQueries + repo facade) | major | L | **Deferred with APNs.** |
| `EntityRepository.upsert` / `ShopwareClient.sync` (/_action/sync) | moderate | S | Add insert-or-update-by-PK path to `EntityRepository.swift` + `sync` to `ShopwareClient.swift`. Standalone primitive; prereq for push token upsert but independently useful. |
| Compact money formatter (fmtMoneyCompact) | minor | S | Add compact variant to `Format.swift`; needed for analytics chart bar labels. Build with Analytics. |

## 3. Recommended build order

**Milestone 1 — Orders/Customers detail wiring (quick wins, mostly S over already-wired backends).**
Internal note, tracking edit, customer note, email/call quick actions (both Orders + Customers), net total, product-number subtitle, QuickLook open, generate-doc confirm, customer "last order"/"customer since" stats, customer summary tiles. Highest ROI: closes 2 major + many moderate/minor gaps with minimal new plumbing.

**Milestone 2 — Products pricing & identifiers.**
Variant tax association (prereq) → linked gross/net price editor across all three sheets + persistence rework → EAN/manufacturer number view+edit. Two majors, cohesive area.

**Milestone 3 — Reviews/Promotions flow richness.**
Generate-codes dialog (major), active-toggle reload + snapshot refresh, promo window line, promo hero, review keep-hidden/reject + status badge, review error/refresh. Mostly S/M, self-contained.

**Milestone 4 — Customer order-history pagination + Media search/pagination.**
Migrate bespoke VMs onto generic `ListingState`; add media search + camera capture. Shared "adopt ListingState / add capture" theme.

**Milestone 5 — Analytics/Reports engine (largest, highest-value single feature).**
Build in order: (a) infra — AnalyticsQueries + AppRepository facade + `fmtMoneyCompact`; (b) date-range bar + KpiType + ReportsViewModel; (c) trend cards w/ prior-period delta + CustomerCount single-number; (d) breakdown cards (7 dimensions); (e) multi-dimension filter sheet; (f) period-aware cross-shop w/ RankBars. Sequenced so each layer is shippable.

**Milestone 6 — WidgetKit extension.**
Add extension target, TimelineProvider, WidgetBundle over existing views; validate App Group cross-process reads. Standalone; can run parallel to M5.

**Milestone 7 — ProductFieldConfig (Products + Shop Settings) + Manage-shops affordances.**
Model + settings toggles + detail gating; add-shop/empty-state on ManageShopsView.

**Milestone 8 — Notification deep-linking + `EntityRepository.upsert`/`sync` primitive.**
Portable-now push items: UNUserNotificationCenterDelegate deep-link into existing local notifications; add the /_action/sync upsert primitive (independently useful, and unblocks a future push token layer).

**Deferred track (call out separately, do not sequence into M1–M8): APNs remote push.**
Server-driven push (APNs) + ce_fcn token registration/upsert + per-shop push-status UI + PushQueries/repo push facade + contextual per-shop permission prompt. Requires product decision (adopt APNs + provision aps-environment entitlement + remote-notification background mode + server-side push gateway) before any of it is worth building. The local-polling architecture already covers notification *type* coverage (orders+reviews always, lowstock+unpaid opt-in), so this is a real-time-delivery upgrade, not a functional hole.

## 4. Explicitly out of scope / deferred

- **APNs remote push and its entire dependency chain** (deferred track above) — blocked on a product/architecture decision; local polling is the intentional current design.
- **In-app update flow** — N/A: Android uses Google Play Core AppUpdateManager; no Apple equivalent (App Store handles updates).
- **Stable per-install push id / FCM token rotation / "push app not installed" probe / connect-wizard push registration** — N/A: all exist solely to serve server-side ce_fcn/FCM, which the Apple port does not use.
- **Two-column/side-by-side tablet dashboard & explicit empty-detail placeholder** — cosmetic layout deltas; NavigationStack split behavior is functionally equivalent. Not counted as gaps.
- **Native swipe actions vs inline buttons (Reviews)** — intentional platform restyle, not a gap.
- **Already-ported items** (do not re-add): guest/disabled status badges, available-stock distinction, price-not-editable hint. Confirmed present, differing only in placement.
