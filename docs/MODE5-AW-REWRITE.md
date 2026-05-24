# Mode 5 AW Rewrite — v1.60 Design Doc

**Status:** in-progress
**Branch:** `mode5-aw-rewrite`
**Target branch:** `feat/recoveri-ea`
**Source version:** v1.53
**Target version:** v1.60

## Goal

Reshape Mode 5 (Partial Recovery) so its **input layout, naming and high-level
flow** match the well-known [AW Recovery EA](https://www.mql5.com/en/blogs/post/736552)
six-section design, while **keeping the protections** RECOVERI added on top in
v1.43–1.53 (`InpEnsureNetPositive`, `InpFirstTicket`, ATR-driven step,
recovery-priority).

The trend-flip handling stack added in v1.43–1.53 and the TF-driven lock-align
routine added in v1.52 are **removed**. AW Recovery does not have them; in
practice they were rarely used and made the trend-flip code path the
hardest-to-reason-about block in the file.

This is a **breaking change for users who relied on those nine inputs**.
Defaults of all other inputs are preserved byte-for-byte.

## Six-section AW input layout

After the rewrite, Mode 5–relevant inputs are organised under these six groups,
in this order, mirroring AW Recovery:

| # | Section | Purpose |
|---|---|---|
| 1 | `=== ORDERS TO RECOVERY ===` | Which orders to manage, priority, lock-on-start |
| 2 | `=== LAUNCH SETTINGS ===` | Trigger (instant / DD% / DD$), disable-other-EAs, slow-start |
| 3 | `=== TAKEPROFIT AND PARTIAL RECOVERY ===` | Basket target, partial-close lot, net-positive guard, TP zone line |
| 4 | `=== RECOVERY GRIDS AND AVERAGE ORDERS ===` | Averager geometry, lot mode, ATR step, max chain |
| 5 | `=== TREND FILTER ===` | MA-cross trend filter, one-per-bar |
| 6 | `=== PROTECTION SETTINGS ===` | Equity stop, spread, virtual TP/SL/BE/TSL, time/news, close-only |

Mode-3 (HedgeLock + auto-unlock), Modes 1/2 (Averaging/Martingale), notifications,
persistence, manual buttons, unconditional grid and panel groups are **kept as
separate input groups** outside these six sections — they are RECOVERI features
that don't map onto AW.

## Changes

### Inputs REMOVED (9 keys)

Trend-flip stack (v1.43–1.53):

| Key | Default | Reason for removal |
|---|---|---|
| `InpRestartGridOnTrendFlip` | true | AW has no trend-flip behaviour; flip handling is done implicitly by trend filter blocking new averagers on the wrong side |
| `InpCloseOldGridOnTrendFlip` | true | Same |
| `InpOldGridCloseProfit` | 0.0 | Was only relevant when the above was true |
| `InpTrendFlipTrimStrong` | false | Same |
| `InpKeepOldGridAlive` | false | Was a 3-way escape hatch on top of the above; redundant after removal |
| `InpSeedNewGridLot` | false | Same |

Lock-align (v1.52):

| Key | Default | Reason for removal |
|---|---|---|
| `InpLockAlignUseTF` | false | AW has no equivalent; periodic re-balancing of net volume diverged too far from the AW model |
| `InpLockAlignTF` | PERIOD_D1 | Subordinate |
| `InpLockAlignThresholdLot` | 0.0 | Subordinate |
| `InpLockAlignOnlyProfit` | true | Subordinate |

### Code REMOVED

| Symbol | Where | Reason |
|---|---|---|
| `AlignLockByTF()` | ~1711 | TF lock alignment — 9 keys gone |
| `IsNewBarTF()` | ~1641 | Helper only used by `AlignLockByTF` |
| `TryCloseOldGridByProfit()` | ~2352 | Trend-flip close-old-grid stack |
| `TrimStrongSideToWeak()` | ~2465 | Trend-flip lock-trim stack |
| `LastAveragerLot()` | ~2298 | Only used by seed-lot machinery |
| `AnyAveragerOpen()` | ~2321 | Only used by seed-lot machinery |
| `ComputeManagedNetVolumes()` | ~2411 | Already dead since v1.51 |
| `g_prCloseOldActive`, `g_prCloseOldSide` | globals | trend-flip close-old |
| `g_prSeedActive`, `g_prSeedSide`, `g_prSeedLot` | globals | seed-lot |
| `g_alignLastBarTime` | global | lock-align |
| GV keys `PR_COA`, `PR_COS`, `PR_SLA`, `PR_SLS`, `PR_SLT` | persistence | follow their globals |

Callsites cleaned in `DoHedgeLock()` (line ~1273) and `DoPartialRecovery()`
(lines ~2068 and ~2097–2200).

### Inputs KEPT (RECOVERI's killer features over AW)

| Key | Why kept |
|---|---|
| `InpEnsureNetPositive` | The whole point of Option B. AW does not enforce net-positive on chip cycles — RECOVERI does. |
| `InpMinNetProfit` | Floor for the above |
| `InpMinNetProfitPct` | Percentage floor (effective floor = `max(InpMinNetProfit, avgProfit*pct/100)`) |
| `InpRecoveryPriority` | AW has equivalent ("What orders to start from"); we keep the existing enum |
| `InpFirstTicket` | RECOVERI extension — pin a specific ticket first; AW has nothing like it |
| `InpAvgStepUseATR` + ATR group | ATR-driven grid step. AW has only fixed step. We keep ours. |
| `InpOverlapAfterN` | RECOVERI's "intelligent close" — closes intermediate averagers on long chains, keeping first+last. AW has equivalent. |
| `InpUseTrendFilter` (MA cross) | Basic trend filter, kept as-is |

### Inputs ADDED (10 keys for AW alignment + UX)

#### Slow Start (Section 2 — LAUNCH SETTINGS)

| Key | Type | Default | Description |
|---|---|---|---|
| `InpUseSlowStart` | bool | false | Enable graduated activation as drawdown deepens |
| `InpSlowStartLossSteps` | int | 3 | Number of escalation buckets before full activity |
| `InpSlowStartLossStepUSD` | double | 50.0 | Loss per bucket; bucket index = floor(currentLoss / step) clamped to [0,Steps] |

The current bucket index gates the **maximum** number of averagers that can be
open on the marked side: `g_prAvgCount* >= currentBucket → no new averager`.
At bucket 0 (no loss yet), no PR-AVG opens. As loss deepens, more averagers
are allowed. Replaces the AW concept of "slow launch in case of drawdown".

#### Dynamic averager lot (Section 4 — RECOVERY GRIDS)

```mql5
enum ENUM_AVG_LOT_MODE
  {
   AVG_LOT_FIXED            = 0,  // 0: InpAvgVolume * InpAvgVolumeMul^k (legacy default)
   AVG_LOT_PCT_OF_LOSING    = 1,  // 1: losingNetVol * InpAvgLotPctOfLosing/100
   AVG_LOT_FROM_LOSS_USD    = 2,  // 2: floatingLoss * InpAvgLotPerLossUSD
   AVG_LOT_MAX_OF_ALL       = 3   // 3: max(FIXED, PCT, FROM_LOSS_USD)
  };
```

| Key | Type | Default | Description |
|---|---|---|---|
| `InpAvgLotMode` | enum | AVG_LOT_FIXED | Lot sizing strategy |
| `InpAvgLotPctOfLosing` | double | 0.0 | Lot = losingSideVolume * pct/100 (0 = ignore) |
| `InpAvgLotPerLossUSD` | double | 0.0 | Lot = floatingLoss * factor (e.g. 0.001 lot per $1 loss) |

The chosen mode is computed first; the result is then capped by `InpMaxLot` and
`NormalizeLot()`, and the chain multiplier `InpAvgVolumeMul^k` is applied on top
**only in FIXED and MAX_OF_ALL modes**. PCT_OF_LOSING and FROM_LOSS_USD ignore
the chain multiplier — their lot already scales with current loss.

`AVG_LOT_FIXED` (default) preserves v1.53 byte-for-byte behaviour.

#### TP zone visualization (Section 3 — TAKEPROFIT)

| Key | Type | Default | Description |
|---|---|---|---|
| `InpDrawTPLine` | bool | true | Draw a horizontal line at the price where the basket reaches `InpTargetProfit` |
| `InpTPLineColor` | color | clrGold | Line colour |

Solving for `tp_price`:

```
For COMBINED basket:
   sum_i lot_i * sign_i * (tp - price_i) * tickValue/tickSize = InpTargetProfit
=> tp = (InpTargetProfit/(tickValue/tickSize) + sum_i lot_i*sign_i*price_i) / sum_i lot_i*sign_i
```

If the denominator is ~0 (perfectly hedged basket), the line is hidden. For
PER_SIDE basket two lines are drawn (BUY target + SELL target).

#### Recovery progress % (Section 3, panel-only — no input)

State:
- `g_initialDrawdown` (double) — captured the first time `IsRecoveryTriggered()`
  fires AND `bs.profit < 0`. Persisted in GV `RC_DD0`. Cleared when `g_prPhase`
  transitions back to `PR_IDLE` (i.e. cycle finished or basket emptied).
- Panel line: `Recovery: 67.3%  (-150.00 → -49.10)`
- Formula: `pct = (1 - currentLoss/initialLoss) * 100` clamped to [-100, 100].
  Negative pct shown when current loss exceeds initial.

#### Status indicator (Section 3, panel-only — no input)

A small coloured rectangle in the panel header, replacing the `STATUS:` text
line as the primary indicator (text line kept for accessibility):

| Colour | Meaning |
|---|---|
| Lime | Recovery running (any PR-AVG/PR-LOCK open or trigger fired) |
| Gold | Standby / armed (trigger configured but not yet fired) |
| Orange | Paused / blocked by time/news |
| Red | Emergency equity stop active |
| Silver | No managed positions, no trigger |

#### Manual "Avg Now" button (Section panel)

| Key | Type | Default | Description |
|---|---|---|---|
| `InpShowAvgNowButton` | bool | true | Show "Avg Now" panel button (Mode 5 only) |

Behaviour:
- Visible and functional only when `InpMode == MODE_PARTIAL_RECOVERY`.
- One click opens a single PR-AVG-{B|S} on the side currently chosen by
  `DoPartialRecovery()`'s "wantBuy/wantSell" logic, ignoring step/bar
  filters but still respecting `InpMaxAveragers`, `InpMaxTrades`,
  `SpreadOK`, `EmergencyStop`. Lot computed by the new lot-mode logic.
- Disabled (greyed) when not in Mode 5.

## Behavioural deltas (user-visible)

| Scenario | v1.53 behaviour | v1.60 behaviour |
|---|---|---|
| Trend filter flips while recovering | Restart counter on new side, optionally close old grid by profit, optionally trim lock | Trend filter just blocks new averagers on the wrong side; old chain dies through its own `InpAvgTPpts` and the chip pairing |
| Slow drift in net volume between BUY/SELL | Periodic TF-driven re-balance trimmed positive-zone positions on the heavy side | No re-balance; net stays as it is until the lock leg is closed by a chip-cycle or basket target |
| First-time entry into deep drawdown | All averagers allowed immediately (subject to step/bar gates) | Slow Start (when enabled) gates count by loss-bucket; old behaviour preserved with `InpUseSlowStart=false` |
| Averager lot sizing | `InpAvgVolume * InpAvgVolumeMul^k` always | Same when `InpAvgLotMode=FIXED` (default); other modes scale with current loss |
| Visual feedback | Status text only | Status colour rectangle, Recovery% on panel, optional TP-zone HLINE on chart |

## Persistence migration

GV keys `PR_COA`, `PR_COS`, `PR_SLA`, `PR_SLS`, `PR_SLT` from v1.43–1.53 are
**erased on first OnInit** of v1.60 by `LoadState()`'s `staleKeys[]` cleanup
(piggy-backing on the existing mode-mismatch path — we add these five keys to
the `staleKeys` list so they get nuked even on the same-mode path). New key
`RC_DD0` is added for `g_initialDrawdown`.

`DoResetState()` is updated to clear `g_initialDrawdown` and to remove `RC_DD0`
from GV; the trend-flip / seed / align cleanup is dropped from the function
body since those globals no longer exist.

## Test plan

| # | Scenario | Expected v1.60 behaviour | Pass criterion |
|---|---|---|---|
| 1 | Existing v1.53 .set file with all defaults loaded into v1.60 | EA initialises, removed inputs are silently ignored by MT5 (set-files don't fail on unknown keys) | Compile OK, OnInit returns SUCCEEDED, panel shows Mode 5 |
| 2 | Open BUY 0.10, let drift -50, watch PR-LOCK | PR_LOCKING → PR_RECOVERING transition; PR-LOCK SELL 0.10 visible | Same as v1.53 |
| 3 | InpAvgLotMode=PCT_OF_LOSING, pct=15, loser 0.10 lot | First averager opens with 0.015 → normalised to 0.01 | Lot ≈ 15% of losing volume, capped by min lot |
| 4 | InpUseSlowStart=true, Steps=3, StepUSD=20, run drawdown to -10/-30/-50/-70 | Bucket index 0/1/2/3 — at -10 no averager, at -30 only 1, at -50 only 2, at -70 only 3 | Maximum chain follows bucket |
| 5 | InpDrawTPLine=true, COMBINED basket | HLINE at computed price, recomputed each tick | Visible line on chart |
| 6 | Trigger fires with bs.profit=-100, then recover to -25 | Panel shows "Recovery: 75.0% (-100.00 → -25.00)" | Correct % |
| 7 | Net-positive guard tested with deep target | When chip would exceed avg profit, chip is reduced/skipped — same as v1.43 | No regression |
| 8 | Restart EA mid-recovery — persistence | PR_RECOVERING phase + averager counts + RC_DD0 restored | No data loss |
| 9 | Switch InpMode 5→3→5 | RC_DD0 wiped on mode change (same as PR_PH today) | Clean state |
| 10 | Compile with `#property strict` | No warnings about unused/orphan symbols | Clean compile |

## Rollback

Two paths back to v1.53 if needed:

1. `git revert` the merge commit on `feat/recoveri-ea`.
2. Hot-fix: re-introduce the nine removed inputs as **inert no-op stubs** in a
   v1.61 patch so old .set files validate cleanly, then plan a v2.0 to
   actually remove them.

## Out of scope (deferred)

These were considered for v1.60 but **not** included to keep the diff focused:

- **AW Trend Predictor filtering** — replacing MA-cross with ATR-breakout + level
  pierce. Deferred to v1.61.
- **Three-panel UI** (current / progress / history) — Recovery% is a single
  panel line for now; full three-panel split is a v1.7x UX milestone.
- **"Possible Closures" preview** on Close-All click — a UX nicety, not blocking
  AW alignment.
- **Smart-close: use existing profits to offset losses** before opening new
  averager — this is `MODE_SMART_CLOSE` (Mode 4) in spirit; cross-mode
  borrowing is a separate design.
