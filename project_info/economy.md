# CurlingChamp Economy Plan (Breeding-First)

## Design Intent

Primary fantasy: build a strong bloodline through breeding + training, then sell elite offspring for profit.

This means:

1. Buying new stones is expensive and requires saving.
2. Match income is helpful but not the main money engine.
3. Best long-term profit comes from selling player-bred stones.
4. Shop refresh is intentionally a bad deal most of the time.

---

## Current Constraints

- Starting cash is 100.
- Season length is 21 weeks.
- Money persistence exists already.
- Auction transaction logic still needs implementation.
- Breeding gameplay is planned, so formulas here define target economy behavior now.

---

## Pacing Targets

### Savings Pressure

- Typical buyable shop stone should cost about 280 to 460.
- High-end genetic seed stone should cost about 500 to 800.
- Average player should need 4 to 8 weeks to afford a high-value stone if they do not sell bred stones.

### Income Hierarchy (Most Important Rule)

Expected income contribution over a full season:

1. Selling bred stones: 45% to 60%
2. Match payouts: 25% to 35%
3. Season bonuses and misc: 10% to 20%

If match income ever exceeds bred-stone selling for most players, rebalance is required.

---

## Stone Value Model

Use one core score for pricing and resale.

Definitions:

- P = power (0 to 100)
- S = spin (0 to 100)
- R = precision (0 to 100)
- PP = power_potential (1 to 100)
- SP = spin_potential (1 to 100)
- RP = precision_potential (1 to 100)
- C = condition (0 to 100)
- A = age
- W = wins

### 1) Performance Score

Performance = 0.33P + 0.30S + 0.37R

### 2) Genetic Score

Genetic = 0.34PP + 0.30SP + 0.36RP

### 3) Composite Stone Score

CoreScore = 0.45 x Performance + 0.55 x Genetic

### 4) Condition and Age Multipliers

Mcond = 0.50 + 0.50 x (C / 100)

Mage = clamp(1.06 - 0.035 x max(A - 1, 0), 0.68, 1.06)

### 5) Small Prestige Bonus

Bwin = min(W, 24) x 1.5

### 6) Final Trade Power

TradePower = CoreScore x Mcond x Mage + Bwin

---

## Buy and Sell Pricing

### Shop Buy Price (expensive by design)

BuyPrice = round_to_5(clamp(70 + 4.1 x TradePower + 3.0 x (week - 1), 140, 900))

Target result:

- Mid stones usually land around 300 to 450.
- Top stones usually land around 550 to 850.

### Base Sell Price (non-bred or generic stone)

SellBase = round_to_5(BuyPrice x 0.50)

This keeps random buying and reselling from being a strong strategy.

---

## Breeding Profit Model (Primary Money Engine)

When a stone is player-bred, apply a breeder premium on sale.

Additional definitions:

- ParentAvgGenetic = average of parent Genetic scores
- OffspringGenetic = offspring Genetic score
- DeltaGene = OffspringGenetic - ParentAvgGenetic
- TrainingInvest = total money spent training this stone

### Breeder Quality Multiplier

Mbreed = clamp(1.00 + 0.012 x DeltaGene, 1.00, 1.35)

### Training Recapture Factor

Mtrain = 1.00 + clamp(0.20 x (TrainingInvest / max(BuyPrice, 1)), 0.0, 0.18)

### Final Bred Sell Price

SellBred = round_to_5(SellBase x Mbreed x Mtrain)

Interpretation:

- Strong offspring with good genes and training can reach about 70% to 95% of shop buy value.
- This makes selling bred stones the best money strategy without creating infinite money from simple flips.

---

## Match Economy (Support Income, Not Main Income)

Definitions:

- wk = week
- opp = opponent skill (1 to 10)
- win = 1 if win, else 0

Base = 16 + 1.0 x (wk - 1)

Difficulty = 1.5 x (opp - 5)

ResultBonus = 20 x win

MatchPayout = round_to_5(max(10, Base + Difficulty + ResultBonus))

Target payout band:

- Loss: about 10 to 30
- Win: about 30 to 55

This keeps matches meaningful but below breeding-sale profits.

---

## Intentional Money Sinks

### 1) Shop Refresh Fee (overpriced by design)

RerollFee = round_to_5(60 + 15 x rerolls_this_week + 2 x (week - 1))

Rule of thumb:

- Expected value gain from one reroll should be about 70% to 85% of fee.
- In other words, rerolling is usually negative EV and should feel like a gamble.

### 2) Training Fee

TrainingFee = 45 + 8 x (year - 1)

Training remains strong but always has opportunity cost.

### 3) Breeding Attempt Fee

BreedFee = 65 + 10 x (year - 1)

This prevents unlimited breeding spam and reinforces selective pairing.

### 4) Weekly Stable Upkeep

UpkeepPerStone = round(4 + 0.015 x BuyPrice)

Encourages a focused roster rather than endless hoarding.

---

## Guardrails

1. Never allow direct arbitrage:
   SellBase must stay <= 0.55 x BuyPrice for same-state stone.
2. Bred premium only applies to stones flagged as bred-by-player.
3. Clamp all prices and payouts to non-negative integer values.
4. Track weekly telemetry:
   money_start, match_income, bred_sale_income, other_income, total_spend, money_end.

---

## Validation Targets

Economy is healthy when all are true:

1. Median player can buy one solid shop stone every 5 to 7 weeks from match income alone.
2. Players who engage breeding + training can buy one solid shop stone every 2 to 4 weeks.
3. Median season profit from bred-stone sales is at least 1.4x median season match income.
4. Shop reroll is used in fewer than 30% of weeks per player on average.

---

## Implementation Priority

1. Add pricing functions for BuyPrice, SellBase, SellBred.
2. Add match payout formula.
3. Add reroll fee before enabling frequent rerolls.
4. Add training fee and breeding fee.
5. Add telemetry counters for validation tuning.

---

## Fast Retuning Rules

If players cannot afford stones at all:

- lower buy coefficient from 4.1 to 3.8, or
- raise win bonus from 20 to 24.

If players can buy too easily without breeding:

- raise buy coefficient from 4.1 to 4.4, or
- reduce base match payout by 3.

If reroll is still too attractive:

- increase reroll base from 60 to 75.

If bred selling is not clearly best:

- increase Mbreed slope from 0.012 to 0.015.
