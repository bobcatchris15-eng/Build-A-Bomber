class_name BlueprintNamer
extends RefCounted
# Generates deadpan designations for player designs: a compound word-pair
# wrapped in military version formatting. "GoatHauler Mk VI", "FoxShaft M38",
# "Type 17 IronDung".
#
# The joke is structural, not written. Nothing in the word lists is trying to
# be funny on its own - "Goat" and "Hauler" are both entirely ordinary. The
# comedy comes from the designation format treating whatever falls out with
# complete bureaucratic seriousness, which is the same "played straight"
# rule the rest of the interface follows. So: no puns, no exclamation marks,
# no words that are already jokes. If a pair lands as absurd, the format
# should still present it as though it came off a procurement form.
#
# Used to SUGGEST a name, never to assign one silently - a design still only
# reaches the match roster when the player commits to a name (see
# blueprint_manager.is_named()). The generator exists because the actual
# annoyance was never "designs have no name", it was "every row in the
# roster is indistinguishable from every other row."

# Deliberately concrete and mundane. Animals, trades, materials, terrain -
# the vocabulary of things that get stencilled on real equipment.
const HEADS = [
	"Goat", "Fox", "Iron", "Mule", "Boar", "Crow", "Elk", "Hog",
	"Stone", "Ash", "Salt", "Coal", "Tin", "Brass", "Clay", "Slag",
	"Badger", "Otter", "Ox", "Ram", "Toad", "Moth", "Wasp", "Vole",
	"Gravel", "Ditch", "Bog", "Fen", "Ridge", "Gulch", "Marsh", "Scrub",
	"Pike", "Drum", "Anvil", "Kettle", "Barrel", "Spade", "Churn", "Flint",
]

# Function-shaped nouns: what a piece of equipment does, or the part of it
# you would grab. Mildly ignoble on purpose - "Shaft" and "Dung" sit in the
# same list as "Hauler" and nothing flags the difference, which is the point.
const TAILS = [
	"Hauler", "Shaft", "Dung", "Digger", "Lifter", "Breaker", "Sled",
	"Cutter", "Grinder", "Pusher", "Winch", "Crank", "Piston", "Sump",
	"Hopper", "Loader", "Rammer", "Scraper", "Dozer", "Tender", "Yoke",
	"Wallow", "Trough", "Bellows", "Gasket", "Flange", "Spindle", "Cog",
	"Warden", "Marshal", "Steward", "Bailiff", "Reaver", "Harrier",
]

# Roman numerals only go as high as the format plausibly would. A "Mk XLVII"
# reads as a joke about roman numerals rather than as equipment.
const ROMAN = [
	"I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X",
	"XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX", "XX",
]

const SUFFIX_LETTERS = ["A", "B", "C", "D", "E", "H", "K", "R", "S", "T"]


# Returns a designation string. Pass an rng for reproducible output (tests);
# omit it for a fresh random name.
static func generate(rng: RandomNumberGenerator = null) -> String:
	var r := rng
	if r == null:
		r = RandomNumberGenerator.new()
		r.randomize()

	var compound: String = HEADS[r.randi() % HEADS.size()] + TAILS[r.randi() % TAILS.size()]

	# Weighted toward the trailing forms - a designation after the name is
	# the more common real-world pattern, and putting "Type 17" in front
	# every other time makes the whole list feel like it has one gimmick.
	match r.randi() % 8:
		0, 1:
			return "%s Mk %s" % [compound, ROMAN[r.randi() % ROMAN.size()]]
		2, 3:
			return "%s M%d" % [compound, r.randi_range(10, 99)]
		4:
			return "Type %d %s" % [r.randi_range(2, 99), compound]
		5:
			return "%s Mk %s%s" % [
				compound,
				ROMAN[r.randi() % ROMAN.size()],
				SUFFIX_LETTERS[r.randi() % SUFFIX_LETTERS.size()]]
		6:
			return "%s-%d%s" % [
				compound,
				r.randi_range(2, 9),
				SUFFIX_LETTERS[r.randi() % SUFFIX_LETTERS.size()]]
		_:
			return "%s No. %d" % [compound, r.randi_range(2, 40)]


# A batch of distinct suggestions, for anywhere that wants to offer a choice
# rather than a single roll. Gives up rather than looping forever if the
# word lists can't produce enough uniques.
static func generate_batch(count: int, rng: RandomNumberGenerator = null) -> Array:
	var out: Array = []
	var attempts := 0
	while out.size() < count and attempts < count * 20:
		var candidate := generate(rng)
		if candidate not in out:
			out.append(candidate)
		attempts += 1
	return out
