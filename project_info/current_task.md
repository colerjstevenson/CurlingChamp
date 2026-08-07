# Current Task: Breeding Screen Plan

## Goal

Implement the breeder scene as a real gameplay menu that supports the full breeding loop:

- selector screen when the breeder is empty
- in-progress screen while breeding is underway
- failed screen when a breeding attempt does not succeed
- success screen when a breeding attempt produces a new stone

Breeding is a core progression system, so the result should feel worth trying often without becoming so punishing that players stop using it.

## Existing Scene Assumption

- The breeder scene already exists.
- It already contains layered UI that can be shown or hidden based on breeder state.
- This task is about wiring the logic and state flow, not rebuilding the scene layout.

## Files Likely To Edit

These are the main files that should be touched for the breeding feature:

- scenes/menus/breeder.tscn - connect the existing layers and controls to the breeding state flow.
- scripts/breeder_menu.gd - new or attached scene script that drives selector, in-progress, failed, and success behavior.
- scripts/game_manager.gd - store breeder state, current pair, remaining weeks, and the generated offspring result.
- scripts/save_file.gd - serialize and deserialize breeder state so the job survives reloads and week changes.
- scripts/stone_data.gd - add or extend helper logic for generating offspring stats, origin, and selling value.
- project_info/economy.md - adjust breeding price and reward assumptions if the implementation needs tuning.

If the scene exposes any missing nodes or still uses placeholder labels, the breeder scene file should be updated first before the new script is wired in.

## Planned Breeder States

### 1. Empty / Selector

Use this when the breeder has no active breeding job.

Player flow:

- choose 2 stones from the roster
- review the pair and preview the likely result
- start breeding

Required behavior:

- prevent selecting the same stone twice
- disable the start action until 2 stones are chosen

### 2. In Progress

Use this when breeding has already started.

Required behavior:

- show the number of weeks remaining
- block starting another breeding job until the current one resolves
- update the screen automatically if the current week advances

### 3. Failed

Use this when a breeding attempt fails.

Required behavior:

- show that the attempt failed
- let the player exit back to the selector
- preserve the selected stones only if the design expects retrying with the same pair, otherwise clear the attempt and let the player choose again

### 4. Success

Use this when a breeding attempt succeeds.

Required behavior:

- generate the new stone
- let the player name the offspring
- let the player add it to the collection or sell it instead
- return to the selector after the outcome is resolved

## Logic Plan

### Breeding Start

When the player confirms a pair:

- save the parent stone references or IDs
- mark the breeder as occupied
- store the finish week or remaining weeks
- seed any preview data needed for the in-progress screen

### Success Chance

The success formula should reward good breeding choices but still leave room for risk.

Guiding rules:

- healthy stones should breed more reliably
- poor condition should noticeably reduce the chance of success
- very bad condition should make failure possible or likely
- the system should still allow occasional losses even with strong parents, so breeding does not become deterministic

Recommended design shape:

- start from a strong base success rate
- apply bonuses for good condition, strong potentials, and compatible parents
- apply penalties for low condition, old age if relevant, and any negative breeder traits
- clamp the result so it never feels impossible or guaranteed

### Offspring Generation

The offspring should feel related to both parents, but not be a perfect copy.

The new stone should:

- inherit a blend of parent traits
- sometimes lean slightly better in one stat and slightly worse in another
- keep enough randomness that each birth feels distinct
- have a strong enough floor that the result is usually usable
- have enough ceiling that a great pair can produce exciting upgrades

Recommended design shape:

- average the parent stats as the baseline
- add a small random variance within a controlled band
- bias the variance upward when the parents are healthy, high quality, or well matched
- bias the variance downward when condition is poor or breeder quality is low

### Economy and Motivation

Breeding should be one of the main reasons to keep playing.

Design goals:

- successful breeding should often produce a meaningful upgrade or a valuable sale option
- failed breeding should sting, but not so much that it feels like wasted time
- the player should want to try again because a better pair can realistically produce a better result
- the best outcomes should feel rare enough to be exciting, but common enough that progress is steady

## UI State Rules

- Selector layer is visible only when no active breeding exists.
- In-progress layer is visible while a breeding job is active.
- Failed layer is visible after a failed attempt until the player dismisses it.
- Success layer is visible after a successful attempt until the player names, stores, or sells the offspring.

## Implementation Order

1. Confirm the breeder scene layer names and the nodes that control visibility.
2. Add or extend the breeder script to own the breeder state and selected pair data.
3. Hook the selector to roster stone selection and start-breeding actions.
4. Add breeder persistence so state survives week changes and scene reloads.
5. Implement the success-rate and offspring-generation formulas.
6. Wire failed and success transitions back into the selector flow.
7. Add preview text and any simple stat display needed for the result screens.
8. Test edge cases like empty roster, poor condition stones, and finishing a breeding job after advancing the week.

## Acceptance Criteria

- The breeder scene opens in the correct layer for its current state.
- The player can select 2 stones and start breeding from the selector.
- The in-progress screen shows a week countdown.
- Failed breeding sends the player to a failure screen and then back to the selector.
- Successful breeding produces a new stone that can be named and either kept or sold.
- The success and failure rates feel fair, with condition mattering clearly but not making breeding miserable.

