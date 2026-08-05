#  "Age Of Dragon ~ AOD" 

We are building a RTS Game "Age Of Dragon" or AOD for short it effectively a age of empire 2 clone with a dragon twist but for mobile. we will reuse all AOE2 mechanics and add a Dragon nest POI, and a Dragon unit that can be trained and used in battle. 
It is a Mobile first game with support for windows and linux built with network with single player campaign via local server planned for V2 release.

 mp global switch
 I have a simple ui design in mind for main game play. @UI_Design.md, and a few idea layouts for planning but nothing final.

the project will be built out in Godot, we need to research if there are any open source project what we can use to fast track the mobile build, even if the souce is not Godot, the overall features for RTS like path finding, unit command, upgrades, build queue and so on are stuff that should have been done before.

we will be building it out in phases, 1-x breaking it down into manageble chunks.

we will have release tags v0.1.0-0.8.9 = alpha, V0.9.0-v0.9.9 = beta, v1.0.0 = release

we will build scenes and scripts with objects and classes inmind for the over all project while delivering the Min Viable Product as a proof of concept

building out the idea, design, look feel and style will be stored in ./idea.md 

implementation and planning for phases and sub phases are stored in plan.md

## Build order

Phases below are ordered so that whatever a phase needs already exists by the time you build it (non-blocking build order). The original brainstorm order is kept in git history / memory if it's ever needed for reference; a few sub-phases are still unavoidably circular (e.g. villagers build buildings, buildings train villagers) and are flagged inline with "(stub until Phase X lands)" where that happens - build the flagged behaviour as a no-op/placeholder first and wire it up for real once the referenced phase exists.

phase 1 - Main Menu
 - using @UI_Sprites/UI_dragon-huds.zip  and @UI_Sprites/uı-fonts.zip  
phase1.1 place holder buttons, PLAY, MULTIPLAYER, SETTINGS, QUIT.
phase1.2 link play with main gameplay scene.

phase2 map design
phase2.1 the world map will be designed with a grid system, each tile will have a type (grass, water, mountain, etc.) movement cost associated with it.
phase2.2 units will be able to move across different tile types based on their movement capabilities, units on land, boats on water. (stub until Phase 4 - Units lands)
phase2.3 the map will also include resource nodes (trees, gold mines, etc.) and buildings that can be interacted with by units. (stub until Phase 5 - Buildings and Phase 6 - Wildlife/Resources land)
phase2.4 the map will be generated procedurally or designed manually to provide a variety of gameplay experiences min 2 player or max8, player count will determine map size.
phase2.5 the map will have a fog of war system, where unexplored areas are hidden from the player until they are revealed by units or buildings. units and buildings will have a vision range that determines how much of the map is visible to the player. after a unit or building is destroyed the area will be hidden again until explored by another unit or building. (vision sources arrive with Phase 4 - Units and Phase 5 - Buildings)
phase2.6 starting conditions, every player starts the match with 5 villagers and 1 town centre placed at their start position. (stub until Phase 4 - Units and Phase 5 - Buildings land)

phase 3 world map and camera control
phase3.1 - world map, will be a isotopic view of the world 
phase3.2 - zoom control, the zoom control is swiping up or down the left or right side of the screen.
phase3.3 - camera control, will be a drag and swipe on the screen to move the camera around the world map, the camera will be limited to the world map size.
phase3.4 - camera reset, double tapping the minimap will reset the camera to the town center of the current player on the world map. (stub until Phase 5 - Buildings lands, no town centre to reset to yet)
phase3.5 - camera follow, when a unit is selected the camera will follow the unit around the world map, if the unit is destroyed or deselected the camera will remain on the last position until a new unit is selected or the camera is moved or reset. (stub until Phase 4 - Units lands)
phase3.6 - tap to move, when a unit is selected tapping on the world map will move the unit to the tapped location (stub until Phase 4 - Units lands)
phase3.7 - tap minimap to move, when a unit is selected tapping on the mini map will move the unit to the tapped location (stub until Phase 4 - Units lands)
phase3.8 - tap minimap with no unit selected will move the camera to the tapped location on the world map.

phase 4 Units - only villagers for MVP, other units will be added later
phase4.1 - tap to move, when a unit is selected tapping on the world map will move the unit to the tapped location if the unit is unable to reach the location due to obstacles or enemies it will stop at the last reachable location.
phase4.2 - pathfinding, the units will use A* pathfinding to navigate around the world map, if the unit is unable to reach the location due to obstacles or enemies it will stop at the last reachable location.
phase4.3 - unit selection, when a unit is tapped it will be selected and the action and selection panel will show the unit's stats and actions.
phase4.4 - unit actions: stop, stand gauard, attack, move, gather resources, build buildings, and special abilities will be available in the action panel when a unit is selected. (gather/build targets are stubs until Phase 5 - Buildings and Phase 6 - Wildlife/Resources land)
phase4.5 - unit actions will be context sensitive, for example if a villager is selected and the player taps on a tree the action panel will show the gather wood action flash, if the player taps on a building the action panel will show the build building action flash, if the player taps on an enemy unit the action panel will show the attack action flash. (tree/building context is a stub until Phase 5 - Buildings and Phase 6 - Wildlife/Resources land)
phase4.6 - unit health, when a unit is selected the unit's health will be shown in the selection panel, if the unit is attacked by enemy units the health will decrease and if the health reaches 0 the unit will be destroyed and removed from the world map. unit health will be restored when the unit is healed by a friendly healing unit or garrisoned in a building. unit health will be a small dot/circle above the unit's sprite on the world map if less than 50% - orange, less than 25% - red.
phase4.7 - unit death, when a unit's health reaches 0 the unit will be destroyed and turn to the death sprite on the world map, if the unit is a villager it will loose any resources it was carrying, after the death the unit i no longer selectable / clickable the death sprite is removed after 60 sec, fading in transarancy will 100% for the last 10 sec.
phase4.8 - unit garrison, when a unit is selected and the player taps on a friendly building the action panel will show the garrison action flash, if the player taps on the garrison action the unit will move to the building and enter it, the unit will be removed from the world map and added to the building's garrison list, if the building is attacked by enemy units the garrisoned units will take damage and if their health reaches 0 they will be destroyed and removed from the building's garrison list. (stub until Phase 5 - Buildings lands)
phase4.9 - defensive garrison, when a unit is garrisoned in a building with defensive capabilities like a town centre,tower or castle the damage the building deals is increased based on the amout of units in the building, a town centre can keep 5, a tower can keep 10, a caste can keep 50. (stub until Phase 5 - Buildings lands)
phase4.10 - unit special abilities, when a unit is selected and the player taps on the special ability action the unit will perform the special ability, if the unit is unable to perform the special ability due to cooldown or lack of resources the action will be greyed out and unclickable.
phase4.11 - population cap, the population cap will be determined by the number of town centres and houses the player has built, each town centre will increase the population cap by 10 and each house will increase the population cap by 5, if the player reaches the population cap they will be unable to build any more units until they build more town centres or houses, cap is set at start of match. (stub until Phase 5 - Buildings lands)

phase 5 buildings - only town centre for MVP, other buildings will be added later
phase5.1 - building placement snap to grid, when a building is selected from the build queue of a villager, after selection it will show a transparent white saturated version of the building, the player can drag the building around the world map to find a suitable location, when the player taps on the world map the building will be placed at that location, if the location is not suitable it will flash red and cancel the placement of the building, the building will go thru the building phases.
phase5.2 - building phases, the building will go thru some phases, each phase will have a different sprite and animation, the building will be destroyed if it is attacked by enemy units.
phase5.3 - building upgrades, when a building is selected in the actions panel, the player can select an upgrade for the building, if the building is not being attacked and the player has enough resources the upgrade will be started and the building will go thru the upgrade phases, each phase will have a different sprite and animation, the building will be destroyed if it is attacked by enemy units.
phase5.4 - building queue, when a building is selected in the actions panel, the player can select a unit to be built, if the player has enough resources and the queue is not full the unit will be added to the build queue, when the unit is built it will be added to the world map on a free tile next to the building.
phase5.5 - building destruction, when a building is attacked by enemy units it will take damage and if the damage is greater than the building's hit points it will be destroyed and turn to the destroyed spite opening the tiles on the world map for new buildings, the building is not selectable and the destroyed sprite will remain until another building is built over one of its tiles.
phase5.6 - building health, when a building is selected the building's health will be shown in the selection panel, if the building is attacked by enemy units the health will decrease and if the health reaches 0 the building will be destroyed and turn to the destroyed spite opening the tiles on the world map for new buildings. building health will be a small dot/circle above the building's sprite on the world map if less than 50% - orange, less than 25% - red.

phase 6 wildlife / resources - only deer, gold and tree for MVP, other wildlife,stone will be added later
phase6.1 - wildlife movement, the wildlife will move around the world map with in a raduis of origenal placement, if the wildlife is attacked by enemy units it will run away from the enemy units selection a new point to roam around in a radius and if it is killed it will render a death sprite on the world map, villager will be able to gather from it until the resource left is 0, then its removed.
phase6.2 - goldmine placement, the goldmine will be placed on the world map at a random location, it cannot take damage, villager will be able to gather from it until the resource left is 0, then its removed. mines come in 3 sizes, small, medium and large, the size will determine the amount of resources available to gather. visually there is no difference between the sizes, the size will be determined by the amount of resources available to gather and the name in unit / building selection panel.
phase6.3 - tree placement, the tree will be placed on the world map at a random location in a random share close together creating a forest, and some random trees scarred around it cannot take damage, villager will be able to gather from it until the resource left is 0, then its removed. trees come in 3 sizes, small, medium and large, the size will determine the amount of resources available to gather. visually there is a skinny dead tree, a oak tree and a palm tree marching the sizes, the size will be determined by the amount of resources available to gather and the name in unit / building selection panel.

phase 7 resource counter column top right
phase7.1 - 5 vertical icons, stone, gold, wood, food and villager count tracked via global variables, will be updated when the resource system is implemented, the villager count will be a fraction of idle/total villagers.

phase 8 main game interface
 - using example @UI_Design.jpg  
phase8.1 unit / building selection panel 
 - 2 smaller pannels inside, 1 left for actions/build and the other right for build /upgrade queue or selected units list or formation.
phase8.2 mini_map and 4 buttons, i like a circle mini map one button in every corner - actions to be confrimed later. possibly [trade (locked behind market building), menu menu, chat, minimize]

phase9 age advancement header top centre
phase9.1 - current age, will be updated when the age advancement system is implemented showing a single roman numeral 1-5 in a gold circle.
phase9.2 - age advancement progress bar, will be visible to the right of the age showing a red bar inside a gold filling indicating upgrade progress during age transitions, depending on screen width it can be below the age.

phase10 - controle groups 
phase10.1 - place holder for later 5 icons just empty circles for a start.
phase10.2 - will only fuction when units phase is complete, using 2 fingers draging away from each other creats a selection box beween the 2 fingers, on release all unit under the box is selected, double tapping any any control group icon adds selected unit to the group.
phase10.3  - will only fuction when units phase is complete,  double tapping any unit onscreen will select all units of the same type, double tapping any control group will add all selected unit to the control group
phase10.4 - the control group icon will be the unit type icon of the unit most represented in the group, if all units are removed from the group it will revert back to a empty circle.

phase11 win condition
phase11.1 - the win condition will be determined by the game mode selected, for example, in a standard game mode the win condition will be to destroy all enemy units and buildings, in a capture the flag mode the win condition will be to capture the enemy's flag and return it to your base, in a king of the hill mode the win condition will be to control a specific area of the map for a certain amount of time. The win condition will be displayed in the start match screen and in the game lobby before the match starts.

phase12 multiplayer and ai
phase12.1 - multiplayer will be implemented using a client-server model, where one player will host the game and the other players will connect to the host's server. The server will handle all game logic and state synchronization between clients.
phase12.2 - AI will be implemented using a state machine, where the AI will have different states (idle, gather resources, build buildings, attack, etc.) and will transition between states based on game events and conditions. The AI will be able to gather resources, build buildings, train units, and attack the player or other AI players based on its current state and strategy. The AI will also have difficulty levels that will affect its decision-making and resource management.

phase13 - dragon unit and dragon nest POI
phase13.1 - the dragon unit will be a powerful unit (same hit points as a castle), capable of flying over obstacles and dealing significant damage to enemy units and buildings (same damage as a castle) but with wings. The dragon unit will have a special ability that can be activated by the player, such as a fire breath attack that deals area damage to enemy units and buildings. and a normal attack that deals damage to a single target. The dragon unit will have a cooldown period for its special ability and will require a certain amount of time to train.

phase13.2 - the dragon nest POI will be a special building that can be found on the world map, and will be guarded by a dragon unit. The dragon nest POI will provide a baby dragon unit to the player who captures it by defeating the dragon. The dragon nest POI will be a high-value target for players to defeat and capture the baby dragon, as it will provide a significant advantage in battle. The dragon nest POI will have a one baby dragon units that can be trained (timer 360sec from defeating the dragon) th, and once all the baby dragon units are trained, the dragon nest POI will be destroyed and removed from the world map. The dragon nest POI will also have a health bar that can be attacked by enemy units, and if the health reaches 0, the dragon nest POI will be destroyed and removed from the world map. The nest is claimed by the player who defeats the dragon and captures the baby dragon, other payers can attack the nest to destroy it and remove it from the world map, but they will not be able to capture the baby dragon. 

