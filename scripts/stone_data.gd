extends RefCounted
class_name Stone

const MIN_VARIANT := 1
const MAX_VARIANT := 51

enum Origin {
	STARTING,  ## Given to the player at the start of the game
	BOUGHT,    ## Purchased from the shop or auction
	BRED,      ## Bred by the player from two parent stones
}

var name: String
var age: int
var wins: int
var variant: int
var origin: Origin = Origin.STARTING

var power: int
var spin: int
var precision: int
var condition: int
var power_potential: int
var spin_potential: int
var precision_potential: int


func _init(
	stone_name: String = "",
	stone_power: int = 0,
	stone_spin: int = 0,
	stone_precision: int = 0,
	stone_condition: int = 0,
	stone_age: int = 1,
	stone_wins: int = 0,
	stone_variant: int = 1,
	stone_power_potential: int = 100,
	stone_spin_potential: int = 100,
	stone_precision_potential: int = 100,
	stone_origin: Origin = Origin.STARTING
) -> void:
	name = stone_name
	power_potential = _clamp_potential(stone_power_potential)
	spin_potential = _clamp_potential(stone_spin_potential)
	precision_potential = _clamp_potential(stone_precision_potential)
	power = mini(_clamp_stat(stone_power), power_potential)
	spin = mini(_clamp_stat(stone_spin), spin_potential)
	precision = mini(_clamp_stat(stone_precision), precision_potential)
	condition = _clamp_stat(stone_condition)
	age = max(stone_age, 0)
	wins = max(stone_wins, 0)
	origin = stone_origin
	variant = _clamp_variant(stone_variant)


func add_win() -> void:
	wins += 1


func set_condition(new_condition: int) -> void:
	condition = _clamp_stat(new_condition)


func set_power(new_power: int) -> void:
	power = mini(_clamp_stat(new_power), power_potential)


func set_spin(new_spin: int) -> void:
	spin = mini(_clamp_stat(new_spin), spin_potential)


func set_precision(new_precision: int) -> void:
	precision = mini(_clamp_stat(new_precision), precision_potential)


func _clamp_stat(value: int) -> int:
	return clampi(value, 0, 100)


func _clamp_potential(value: int) -> int:
	return clampi(value, 1, 100)


func _clamp_variant(value: int) -> int:
	return clampi(value, MIN_VARIANT, MAX_VARIANT)


## Calculates the stone's trade power score based on the economy plan.
## Returns a float representing TradePower, which drives buy/sell pricing.
## week: current week number (1-based). age: stone age in years. wins: career wins.
func calculate_value(week: int = 1) -> float:
	# Performance Score
	var performance: float = (0.33 * power) + (0.30 * spin) + (0.37 * precision)

	# Genetic Score
	var genetic: float = (0.34 * power_potential) + (0.30 * spin_potential) + (0.36 * precision_potential)

	# Composite Core Score
	var core_score: float = (0.45 * performance) + (0.55 * genetic)

	# Condition Multiplier
	var m_cond: float = 0.50 + 0.50 * (condition / 100.0)

	# Age Multiplier
	var m_age: float = clampf(1.06 - 0.035 * maxf(age - 1, 0), 0.68, 1.06)

	# Win Prestige Bonus
	var b_win: float = minf(wins, 24) * 1.5

	# Final Trade Power
	var trade_power: float = (core_score * m_cond * m_age) + b_win

	return trade_power


## Returns the shop buy price for this stone at the given week.
func calculate_buy_price(week: int = 1) -> int:
	var trade_power := calculate_value(week)
	var raw: float = 70.0 + (4.1 * trade_power) + (3.0 * (week - 1))
	return int(snappedf(clampf(raw, 140.0, 900.0), 5.0))


## Returns the sell price for this stone at the given week.
## Bred stones receive a breeder premium based on their genetic score vs parent average.
## parent_avg_genetic: average genetic score of the two parents (pass 0.0 for non-bred stones).
## training_invest: total gold spent training this stone.
func calculate_sell_price(week: int = 1, parent_avg_genetic: float = 0.0, training_invest: float = 0.0) -> int:
	var buy_price := calculate_buy_price(week)
	var sell_base := buy_price * 0.50

	if origin != Origin.BRED:
		return int(snappedf(sell_base, 5.0))

	var genetic: float = (0.34 * power_potential) + (0.30 * spin_potential) + (0.36 * precision_potential)
	var delta_gene := genetic - parent_avg_genetic
	var m_breed := clampf(1.00 + 0.012 * delta_gene, 1.00, 1.35)
	var m_train := 1.00 + clampf(0.20 * (training_invest / maxf(buy_price, 1.0)), 0.0, 0.18)
	return int(snappedf(sell_base * m_breed * m_train, 5.0))
