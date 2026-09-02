# The Dragon Born

## Scenario 1: The Ash of Home

### Name

The Shadow Falls

### Objective

Escape the destroyed village with Jack and reach the mountain pass to the East.

### Triggers

* **Start Story Msg:** "The King's Guard struck without warning, razing the peaceful village of Oakhaven. Jack's home is ablaze, and his parents have fallen protecting him. He must run."
* **Parent Death Event:** `Mom` = Killed, `Dad` = Killed
* **Jack Moves to Area:** `Jack` enters `Area_MountainPass` -> Msg: "Jack breaks through the enemy line, escaping into the wild unknown."

---

## Scenario 2: A New Beginning

### Name

A Quiet Shelter

### Objective

Gather resources and construct a hidden homestead to survive in the wilderness.

### Triggers

* **Start Story Msg:** "Wandering into the unsettled borderlands, Jack finds a secluded clearing. To survive the coming winter, he must build a home from scratch."
* **Build Requirements:** `House` = 1, `Mill` = 1, `Farm` = 2
* **Completion Event:** Buildings complete -> Msg: "The small homestead is complete. It isn't much, but it's a place to rest."

---

## Scenario 3: The Dying Message

### Name

Whispers of the Last Hatchling

### Objective

Fend off the rogue intruder and explore the Southern Peaks.

### Triggers

* **Start Story Msg:** "Life on the farm is peaceful until an exhausted, wounded King's Guard stumbles onto the property."
* **Unit Killed:** `Soldier1` killed -> Msg: "With his final breath, the soldier gasps: 'The King seeks it... the last dragon... hidden in the southern caves... do not let him...'"
* **Jack Moves to Area:** `Jack` enters `Area_SouthCaves` -> Msg: "Deep within the caverns, Jack discovers a glowing egg cracking open."

---

## Scenario 4: The Bonding

### Name

Fire and Soul

### Objective

Escort the Baby Dragon back to the homestead without being detected by enemy patrols.

### Triggers

* **Start Story Msg:** "A baby dragon hatches and instantly bonds with Jack, unlocking latent heroic powers within him."
* **Hero Transformation:** `Jack` converts to `Jack_Hero` (Gains stat boost and active abilities)
* **Stealth Movement:** `Jack_Hero` & `Baby_Dragon` enter `Area_Homestead` -> Msg: "You have safely hidden the dragon inside the barn. Keep it secret from the King's scouts."

---

## Scenario 5: Discovery

### Name

Flames in the Night

### Objective

Survive the surprise assault on the homestead and retreat to the Allied rebel camp.

### Triggers

* **Start Story Msg:** "The King's commander tracked the wounded soldier. They have found the homestead—and the dragon."
* **Base Destroyed Event:** `Homestead_Barn` destroyed -> Msg: "They found the dragon! The homestead is lost!"
* **Jack Moves to Area:** `Jack_Hero` enters `Area_RebelCamp` -> Msg: "Jack and the young dragon reach the rebel hideout, seeking allies."

---

## Scenario 6: The Spark of Rebellion

### Name

An Alliance Forged

### Objective

Work with AI Ally (Rebel Leader Vance) to establish a forward military base and recruit an army.

### Triggers

* **Start Story Msg:** "Rebel Leader Vance agrees to fight alongside Jack, inspired by the return of a Dragon Rider."
* **AI Player Action:** `Player_2_AI` (Rebel Vanguard) begins sending resource gifts and defensive patrols.
* **Build Requirement:** `Barracks` = 2, `Blacksmith` = 1, Train `Spearman` = 10
* **Target Destroyed:** Destroy `King_Outpost_West` -> Msg: "The King's forward camp is in ruins! The locals are flocking to your banner!"

---

## Scenario 7: Securing the Border

### Name

Clearing the Pass

### Objective

Eliminate the enemy commander guarding the mountain choke-point alongside your AI Ally.

### Triggers

* **Start Story Msg:** "To march on the capital, Jack and Vance must secure the iron pass controlled by Lord Vane."
* **Unit Killed:** `Lord_Vane` killed -> Msg: "Lord Vane has fallen! The road to the heartland is open."
* **AI Joint Attack:** `Player_2_AI` triggers full assault wave on `Area_PassFortress`.

---

## Scenario 8: The Growing Dragon

### Name

Wings of Thunder

### Objective

Protect the Dragon's Roost for 10 minutes while the dragon completes its growth into an adult war beast.

### Triggers

* **Start Story Msg:** "The King sends wave after wave of siege engines to slay the dragon before it matures."
* **Timer Event:** `Timer_DragonGrowth` reaches 0:00 -> `Baby_Dragon` converts to `Adult_Dragon_Hero`.
* **Completion Msg:** "The dragon takes flight! Rain fire upon the King's forces!"

---

## Scenario 9: Breaking the Chains

### Name

The Liberation of Oakhaven

### Objective

Liberate Jack's home town and destroy the regional garrison.

### Triggers

* **Start Story Msg:** "Jack returns to where it all started. Oakhaven is now an enemy stronghold."
* **Build Specific Building:** Construct `Town_Center` in `Area_OakhavenRuins`
* **Area Cleared:** `Area_Oakhaven` enemy count = 0 -> Msg: "Oakhaven is free! The villagers join the army as elite militia."

---

## Scenario 10: Siege of the Iron Fortress

### Name

At the King's Gate

### Objective

Destroy the outer gate towers and escort siege weapons to the inner courtyard.

### Triggers

* **Start Story Msg:** "The King has retreated behind the impenetrable walls of the Royal Citadel."
* **Specific Unit Destroyed:** `Gate_Tower_Left` & `Gate_Tower_Right` destroyed
* **Unit in Area:** `Trebuchet_1` enters `Area_Courtyard` -> Msg: "The inner walls are breaching! Prepare for the final assault!"

---

## Scenario 11: The Battle of the Royal Citadel

### Name

War of Two Crowns

### Objective

Coordinate with AI Ally Vance to destroy the enemy production buildings and isolate the King.

### Triggers

* **Start Story Msg:** "The final battle rages through the city streets. Vance's forces attack from the east while Jack strikes from the south."
* **Target Destroyed:** Destroy all 4 `Royal_Military_Camps`
* **Speech Msg:** `King_Malthus` -> "You think a oversized lizard makes you a ruler, boy? Come then!"

---

## Scenario 12: The Dragon Born

### Name

A New Dawn

### Objective

Kill King Malthus and reclaim the throne.

### Triggers

* **Start Story Msg:** "The citadel courtyard is quiet. Only King Malthus and his elite guard stand between Jack and justice."
* **Target Unit Killed:** `King_Malthus` killed -> Msg: "You killed the bad dude, Congrats!! The tyrant is no more!"
* **Victory Event:** `Jack_Hero` & `Adult_Dragon_Hero` enter `Area_ThroneRoom` -> Msg: "The realm is restored. Hail the Dragon Born!"