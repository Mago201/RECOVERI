# RECOVERI Changelog

## v1.60 (this release)

**Mode 5 rewrite for AW Recovery alignment.** See [docs/MODE5-AW-REWRITE.md](docs/MODE5-AW-REWRITE.md) for the full design doc.

- Inputs reorganised into six AW-style sections: ORDERS TO RECOVERY / LAUNCH / TAKEPROFIT+PARTIAL / RECOVERY GRIDS / TREND FILTER / PROTECTION.
- **REMOVED** trend-flip handling stack (six keys from v1.43–1.53): `InpRestartGridOnTrendFlip`, `InpCloseOldGridOnTrendFlip`, `InpOldGridCloseProfit`, `InpTrendFlipTrimStrong`, `InpKeepOldGridAlive`, `InpSeedNewGridLot`. Trend filter now simply blocks new averagers on the wrong side, the old chain dies through its own `InpAvgTPpts` and the chip pairing — same as AW Recovery.
- **REMOVED** TF lock-align (four keys from v1.52): `InpLockAlignUseTF`, `InpLockAlignTF`, `InpLockAlignThresholdLot`, `InpLockAlignOnlyProfit`. Functions `AlignLockByTF()`, `IsNewBarTF()`, `TryCloseOldGridByProfit()`, `TrimStrongSideToWeak()`, `LastAveragerLot()`, `AnyAveragerOpen()`, `ComputeManagedNetVolumes()` and the corresponding globals/GV-keys all gone.
- **NEW** Slow Start: `InpUseSlowStart` + `InpSlowStartLossSteps` + `InpSlowStartLossStepUSD` graduate the maximum number of open averagers by floating-loss bucket. Off by default.
- **NEW** Dynamic averager lot: `InpAvgLotMode` enum adds `PCT_OF_LOSING` / `FROM_LOSS_USD` / `MAX_OF_ALL` on top of the legacy `FIXED` mode. Default `FIXED` preserves v1.53 byte-for-byte behaviour.
- **NEW** TP-zone visualization: `InpDrawTPLine` + `InpTPLineColor` draw an `OBJ_HLINE` at the price the current basket needs to reach `InpTargetProfit`. Two lines drawn for `BASKET_PER_SIDE`.
- **NEW** Recovery progress %: panel shows `Recovery: 67.3% (-150.00 → -49.10)` while a cycle is active. Initial drawdown captured the first tick after start trigger fires AND `bs.profit < 0`. Persisted in GV `RC_DD0`. Cleared on `PR_IDLE` re-entry / mode change / Reset State.
- **NEW** Status colour rectangle on the panel: lime/gold/orange/red/silver indicating running/standby/blocked/emergency-stop/idle.
- **NEW** Manual "Avg Now" panel button (Mode 5 only, opt-in via `InpShowAvgNowButton`): opens a single PR-AVG on the side currently preferred by `DoPartialRecovery()`, ignoring step/bar gates but respecting `MaxAveragers`/`MaxTrades`/`SpreadOK`/`EmergencyStop`.
- **KEPT** RECOVERI's killer features over AW: `InpEnsureNetPositive` + `InpMinNetProfit` + `InpMinNetProfitPct` (net-positive guard on chip cycles), `InpFirstTicket` (pin-a-ticket), `InpRecoveryPriority` (HARD / EASY / FIRST_TICKET), `InpAvgStepUseATR` + ATR group, `InpOverlapAfterN` (intelligent close).
- Forward migration: the five GV keys `PR_COA`, `PR_COS`, `PR_SLA`, `PR_SLS`, `PR_SLT` from v1.43–1.53 are erased on first OnInit of v1.60 (added to `staleKeys[]`).

## v1.53

**Mode 5 — parallel grids on trend flip.**

- `InpKeepOldGridAlive` (default false): when the trend filter flips, the old averager grid is left alone — neither the basket flush by `InpCloseOldGridOnTrendFlip` nor the one-shot lock trim (`InpTrendFlipTrimStrong`) fire. Old `PR-AVG-*` close on their own `InpAvgTPpts` + the chip pairing. The new grid runs in parallel under the new trend.
- `InpSeedNewGridLot` (default false): on flip, capture the lot of the last `PR-AVG-*` averager on the abandoned side and use it as the BASE lot for the new side instead of `InpAvgVolume`. The seed stays armed until both grids close.
- Seed state persisted via GV `PR_SLA` / `PR_SLS` / `PR_SLT`.

## v1.52

**Mode 5 — ATR-driven step + TF lock alignment.**

- ATR-driven averager step: `InpAvgStepUseATR=true`, `InpAvgStepATRTF` (default D1), `InpAvgStepATRPeriod` (14), `InpAvgStepATRMul` (0.5), `InpAvgStepATRMin` (floor in points). Effective step = `ATR(TF, period) / Point * Mul`, then `InpAvgStepMul^chainIdx` is applied on top.
- Periodic TF-driven lock alignment: `InpLockAlignUseTF=true`, `InpLockAlignTF` (D1), `InpLockAlignThresholdLot`, `InpLockAlignOnlyProfit`. Once per new bar of the chosen TF the heavy side was trimmed down to the light one, preferring profitable positions ("positive zone").

## v1.51 — fix

**Mode 5 trend-flip trim now targets the lock specifically.**

- v1.50 trim summed imbalance across ALL managed positions and sorted candidates by PnL DESC, so the lock leg (largest PnL) was closed first and absorbed the entire diff including averager volume — closing the lock far more than intended.
- v1.51: trim counts only `lockVol` on one side and `origVol` (no `PR-*` tag) on the other, and trims the lock leg to match the opposite original. Averagers and same-side originals are not touched.

## v1.50

**Mode 5 — optional one-shot trim on trend flip (`InpTrendFlipTrimStrong`).**

## v1.44

**Mode 5 — close old averager grid by combined profit on trend flip.**

- `InpCloseOldGridOnTrendFlip` (default true) + `InpOldGridCloseProfit` (default 0): on flip, sum PnL of all `PR-AVG-*` on the abandoned side; once the sum crosses the threshold, close them all in one pass. Lock leg + originals untouched. State persisted via GV `PR_COA` / `PR_COS`.

## v1.43

**Mode 5 — net-positive guard + grid restart on trend flip.**

- `InpEnsureNetPositive` (default true): chip lot is now sized dynamically so that `avgProfit + chipPnL >= InpMinNetProfit`. Falls back to legacy fixed `InpPartCloseLot` when set to `false`.
- `InpRestartGridOnTrendFlip` (default true): on flip, reset averager counter and one-per-bar gate on the new side so a fresh chain starts immediately at base lot/step.

## v1.42

- Fix: panel buttons now reliable in Strategy Tester Visual mode. `OnChartEvent` delivers `CHARTEVENT_OBJECT_CLICK` unreliably under MT5 visual tester; `PollPanelButtons()` polls `OBJPROP_STATE` every tick. Active only when `MQL_TESTER=true`; live behaviour unchanged.

## v1.41

- Persistence-state mode-mismatch protection: GV `MODE` stamp; when `InpMode` differs from saved mode, mode-specific keys (`LK_*`, `PR_PH`, `RC_TRIG`, `OEAS_DIS`) are cleared. PAUSED / ESTOP / BE / TSL preserved.
- "Reset State" panel button + `DoResetState()` zeroes runtime flags and erases the matching GV keys.
- `OnInit()` logs load status (clean / loaded / mode-mismatch).

## v1.40 "ULTIMATE"

- New `MODE_PARTIAL_RECOVERY` (Mode 5): lock + averagers + partial close of the worst losing position via `PositionClosePartial` — every profitable averager closes itself AND chips the loser.
- Standby-mode: start trigger (`Instant` / `DD %` / `DD $`) — `InpStartTrigger`.
- Trend filter for averagers (MA fast/slow on higher TF) — `InpUseTrendFilter`.
- One-per-bar gate — `InpOneOrderPerBar`.
- Closing overlap — `InpOverlapAfterN` (keep first+last on long chains).
- Recovery priority — `InpRecoveryPriority` (EASY / HARD / FIRST_TICKET).
- Email notifications added to Alert/Sound/Push.
- Disable other EAs at trigger — `InpDisableOtherEAs` (none / same-symbol / all-symbols).

## v1.31

- Manual BUY/SELL panel buttons (for Strategy Tester Visual + live).
- All input prompts translated to Russian.

## v1.30

- HedgeLock auto-unwind FSM: `IDLE → LOCKED → UNWOUND → (RELOCKED) → ...` with profit-target / TSL leg closure and optional partial relock.
- Validation: `InpLockTriggerLoss > 0`.
- Fix: `g_gridPlaced` only set on actual successful grid placement.

## v1.20

- Per-position virtual TSL.
- Notifications: Alert / Sound / Push.
- Persistence via `GlobalVariables`.
- Unconditional grid of pending limit orders.

## v1.10

- Per-side basket close (BUY/SELL independent baskets).
- Virtual TP / SL / breakeven per position.
- Panel: Close All / Pause / Lock Now / etc.
- Time and economic-calendar (MT5 native) filters.
