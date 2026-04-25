-- ================================================================
-- fivesawUtils.lua
-- All-in-one bundled library for Pathfinding, Movements, etc.
-- 1:1 MightyMiner Baritone Port + Humanized Execution
-- ================================================================
local __bundle_preload = {}
local __bundle_loaded = {}
local function __bundle_require(modname)
    if __bundle_loaded[modname] then return __bundle_loaded[modname] end
    if __bundle_preload[modname] then
        local res = __bundle_preload[modname]()
        __bundle_loaded[modname] = res or true
        return __bundle_loaded[modname]
    end
    return require(modname) -- fallback to standard require
end

__bundle_preload["libs/fivetone/action_costs"] = function()
    -- ================================================================
    -- Fivetone / action_costs.lua
    -- 1:1 port of com.jelly.mightyminerv2.pathfinder.costs.ActionCosts
    -- All Minecraft movement physics constants
    -- ================================================================
    
    local ActionCosts = {}
    ActionCosts.__index = ActionCosts
    
    --- Creates a new ActionCosts instance with configurable movement factors.
    --- @param sprintFactor number Sprint movement factor (default 0.13)
    --- @param walkFactor number Walking movement factor (default 0.10)
    --- @param sneakFactor number Sneaking movement factor (default 0.03)
    --- @param jumpBoostLevel number Jump boost potion amplifier (-1 = none)
    --- @return table ActionCosts instance
    function ActionCosts.new(sprintFactor, walkFactor, sneakFactor, jumpBoostLevel)
        sprintFactor   = sprintFactor   or 0.13
        walkFactor     = walkFactor     or 0.10
        sneakFactor    = sneakFactor    or 0.03
        jumpBoostLevel = jumpBoostLevel or -1
    
        local self = setmetatable({}, ActionCosts)
    
        self.INF_COST = 1e6
    
        -- Movement cost calculations (mirrors Kotlin exactly)
        self.ONE_BLOCK_WALK_COST   = 1 / ActionCosts._actionTime(ActionCosts._getWalkingFriction(walkFactor))
        self.ONE_BLOCK_SPRINT_COST = 1 / ActionCosts._actionTime(ActionCosts._getWalkingFriction(sprintFactor))
        self.ONE_BLOCK_SNEAK_COST  = 1 / ActionCosts._actionTime(ActionCosts._getWalkingFriction(sneakFactor))
    
        self.ONE_BLOCK_WALK_IN_WATER_COST   = 20 * ActionCosts._actionTime(ActionCosts._getWalkingInWaterFriction(walkFactor))
        self.ONE_BLOCK_WALK_OVER_SOUL_SAND_COST = self.ONE_BLOCK_WALK_COST * 2
    
        self.WALK_OFF_ONE_BLOCK_COST = self.ONE_BLOCK_WALK_COST * 0.8
        self.CENTER_AFTER_FALL_COST  = self.ONE_BLOCK_WALK_COST * 0.2
    
        self.SPRINT_MULTIPLIER = walkFactor / sprintFactor
    
        -- Ladder costs
        self.ONE_UP_LADDER_COST   = 1 / (0.12 * 9.8)  -- 1 / (0.12b/t upward velocity * gravity)
        self.ONE_DOWN_LADDER_COST = 1 / 0.15            -- 1 / 0.15b/t downward velocity
    
        -- Pre-compute N-block fall cost table [0..256]
        self.N_BLOCK_FALL_COST = self:_generateNBlocksFallCost()
    
        -- Jump cost — simulates jump physics to discourage unnecessary jumping
        local vel = 0.42 + (jumpBoostLevel + 1) * 0.1
        local height = 0.0
        local time = 1.0
        for _ = 1, 20 do
            height = height + vel
            vel = (vel - 0.08) * 0.98
            if vel < 0 then break end
            time = time + 1
        end
        self.JUMP_ONE_BLOCK_COST = time + self:fallDistanceToTicks(height - 1)
    
        return self
    end
    
    --- Friction calculation for walking on ground.
    --- @param landMovementFactor number
    --- @return number friction
    function ActionCosts._getWalkingFriction(landMovementFactor)
        return landMovementFactor * ((0.16277136) / (0.91 * 0.91 * 0.91))
    end
    
    --- Friction calculation for walking in water.
    --- @param landMovementFactor number
    --- @return number friction
    function ActionCosts._getWalkingInWaterFriction(landMovementFactor)
        return 0.02 + (landMovementFactor - 0.02) * (1.0 / 3.0)
    end
    
    --- Converts friction to movement time.
    --- @param friction number
    --- @return number time
    function ActionCosts._actionTime(friction)
        return friction * 10
    end
    
    --- Calculates the vertical velocity at a given tick during freefall.
    --- @param tick number Tick count
    --- @return number velocity (positive = downward distance per tick)
    function ActionCosts:motionYAtTick(tick)
        local velocity = -0.0784000015258789
        for _ = 1, tick do
            velocity = (velocity - 0.08) * 0.9800000190734863
        end
        return velocity
    end
    
    --- Converts a fall distance to the number of ticks it takes.
    --- @param distance number Fall distance in blocks
    --- @return number ticks
    function ActionCosts:fallDistanceToTicks(distance)
        if distance == 0 then return 0 end
        local tmpDistance = distance
        local tickCount = 0
        while true do
            local fallDistance = self:_downwardMotionAtTick(tickCount)
            if tmpDistance <= fallDistance then
                return tickCount + tmpDistance / fallDistance
            end
            tmpDistance = tmpDistance - fallDistance
            tickCount = tickCount + 1
        end
    end
    
    --- Downward motion (distance fallen) at a specific tick.
    --- @param tick number
    --- @return number distance
    function ActionCosts:_downwardMotionAtTick(tick)
        return (math.pow(0.98, tick) - 1) * -3.92
    end
    
    --- Generates the lookup table for N-block fall costs.
    --- @return table Array indexed 0..256 with tick costs
    function ActionCosts:_generateNBlocksFallCost()
        local timeCost = {}
        for i = 0, 256 do timeCost[i] = 0 end
    
        local currentDistance = 0
        local targetDistance = 1
        local tickCount = 0
    
        while true do
            local velocityAtTick = self:_downwardMotionAtTick(tickCount)
    
            if currentDistance + velocityAtTick >= targetDistance then
                timeCost[targetDistance] = tickCount + (targetDistance - currentDistance) / velocityAtTick
                targetDistance = targetDistance + 1
                if targetDistance > 256 then break end
                -- don't increment tickCount; re-check same tick for next target
            else
                currentDistance = currentDistance + velocityAtTick
                tickCount = tickCount + 1
            end
        end
    
        return timeCost
    end
    
    return ActionCosts
    
end

__bundle_preload["libs/fivetone/path_node"] = function()
    -- ================================================================
    -- Fivetone / path_node.lua
    -- 1:1 port of com.jelly.mightyminerv2.pathfinder.calculate.PathNode
    -- ================================================================
    
    local PathNode = {}
    PathNode.__index = PathNode
    
    --- Creates a new path node.
    --- @param x number Block X coordinate
    --- @param y number Block Y coordinate
    --- @param z number Block Z coordinate
    --- @param goal table Goal object with :heuristic(x,y,z) method
    --- @return table PathNode instance
    function PathNode.new(x, y, z, goal)
        local self = setmetatable({}, PathNode)
        self.x = x
        self.y = y
        self.z = z
        self.costSoFar    = 1e6                      -- gCost (starts at INF)
        self.costToEnd    = goal:heuristic(x, y, z)   -- hCost from goal heuristic
        self.totalCost    = 1.0                        -- fCost (will be set properly)
        self.heapPosition = -1                         -- -1 = not in heap
        self.parentNode   = nil                        -- parent for path reconstruction
        return self
    end
    
    --- Polynomial hash for closed-set keying.
    --- Matches the Kotlin implementation exactly:
    ---   hash = 3241
    ---   hash = 3457689 * hash + x
    ---   hash = 8734625 * hash + y
    ---   hash = 2873465 * hash + z
    --- @param x number
    --- @param y number
    --- @param z number
    --- @return number 64-bit hash (Lua 5.3 integers)
    function PathNode.longHash(x, y, z)
        local hash = 3241
        hash = 3457689 * hash + x
        hash = 8734625 * hash + y
        hash = 2873465 * hash + z
        return hash
    end
    
    --- Equality check by position.
    --- @param other table Another PathNode
    --- @return boolean
    function PathNode:equals(other)
        return self.x == other.x and self.y == other.y and self.z == other.z
    end
    
    --- Returns position as a simple table.
    --- @return table {x, y, z}
    function PathNode:getBlock()
        return { x = self.x, y = self.y, z = self.z }
    end
    
    --- Debug string representation.
    --- @return string
    function PathNode:__tostring()
        return string.format(
            "PathNode(x:%d y:%d z:%d g:%.2f h:%.2f f:%.2f)",
            self.x, self.y, self.z,
            self.costSoFar, self.costToEnd, self.totalCost
        )
    end
    
    return PathNode
    
end

__bundle_preload["libs/fivetone/binary_heap"] = function()
    -- ================================================================
    -- Fivetone / binary_heap.lua
    -- 1:1 port of BinaryHeapOpenSet.kt
    -- Min-heap with relocate (decrease-key) via heapPosition tracking
    -- ================================================================
    
    local BinaryHeap = {}
    BinaryHeap.__index = BinaryHeap
    
    --- Creates a new binary min-heap.
    --- @param initialSize number Initial array capacity (default 1024)
    --- @return table BinaryHeap instance
    function BinaryHeap.new(initialSize)
        initialSize = initialSize or 1024
        local self = setmetatable({}, BinaryHeap)
        self.items = {}    -- 1-indexed array of PathNode
        self.size  = 0
        return self
    end
    
    --- Adds a node to the heap and bubbles it up.
    --- @param node table PathNode with .totalCost and .heapPosition fields
    function BinaryHeap:add(node)
        self.size = self.size + 1
        node.heapPosition = self.size
        self.items[self.size] = node
        self:relocate(node)
    end
    
    --- Bubbles a node up from its current heapPosition (decrease-key).
    --- Called after reducing a node's totalCost, or after add().
    --- @param node table PathNode
    function BinaryHeap:relocate(node)
        local pos = node.heapPosition
        local parent = math.floor(pos / 2)  -- integer division (ushr 1 in Kotlin)
    
        while pos > 1 do
            local parentNode = self.items[parent]
            if node.totalCost >= parentNode.totalCost then
                break
            end
            -- Swap parent down
            self.items[pos] = parentNode
            parentNode.heapPosition = pos
            self.items[parent] = node
            node.heapPosition = parent
            -- Move up
            pos = parent
            parent = math.floor(pos / 2)
        end
    end
    
    --- Extracts and returns the minimum-cost node.
    --- @return table PathNode with lowest totalCost
    function BinaryHeap:poll()
        local itemToPoll = self.items[1]
        itemToPoll.heapPosition = -1
    
        local itemToSwap = self.items[self.size]
        self.items[self.size] = nil
        self.size = self.size - 1
    
        if self.size <= 0 then
            return itemToPoll
        end
    
        itemToSwap.heapPosition = 1
        self.items[1] = itemToSwap
        local itemToSwapCost = itemToSwap.totalCost
    
        if self.size <= 1 then
            return itemToPoll
        end
    
        -- Sift down
        local parentIndex = 1
        local smallestChildIndex = 2
    
        while smallestChildIndex <= self.size do
            local rightChildIndex = smallestChildIndex + 1
    
            if rightChildIndex <= self.size
               and self.items[rightChildIndex].totalCost < self.items[smallestChildIndex].totalCost then
                smallestChildIndex = rightChildIndex
            end
    
            if self.items[smallestChildIndex].totalCost >= itemToSwapCost then
                break
            end
    
            -- Swap smallest child up
            local swapTemp = self.items[smallestChildIndex]
            swapTemp.heapPosition = parentIndex
            self.items[parentIndex] = swapTemp
            itemToSwap.heapPosition = smallestChildIndex
            self.items[smallestChildIndex] = itemToSwap
    
            parentIndex = smallestChildIndex
            smallestChildIndex = parentIndex * 2  -- parentIndex shl 1
        end
    
        return itemToPoll
    end
    
    --- Returns true if the heap is empty.
    --- @return boolean
    function BinaryHeap:isEmpty()
        return self.size <= 0
    end
    
    return BinaryHeap
    
end

__bundle_preload["libs/fivetone/movement_result"] = function()
    -- ================================================================
    -- Fivetone / movement_result.lua
    -- 1:1 port of com.jelly.mightyminerv2.pathfinder.movement.MovementResult
    -- ================================================================
    
    local MovementResult = {}
    MovementResult.__index = MovementResult
    
    --- Creates a new mutable result container.
    --- @return table MovementResult instance
    function MovementResult.new()
        local self = setmetatable({}, MovementResult)
        self.x    = 0
        self.y    = 0
        self.z    = 0
        self.cost = 1e6
        return self
    end
    
    --- Sets the destination coordinates.
    --- @param x number
    --- @param y number
    --- @param z number
    function MovementResult:set(x, y, z)
        self.x = x
        self.y = y
        self.z = z
    end
    
    --- Resets all fields to defaults.
    function MovementResult:reset()
        self.x    = 0
        self.y    = 0
        self.z    = 0
        self.cost = 1e6
    end
    
    --- Returns destination as a simple table.
    --- @return table {x, y, z}
    function MovementResult:getDest()
        return { x = self.x, y = self.y, z = self.z }
    end
    
    return MovementResult
    
end

__bundle_preload["libs/fivetone/movement_helper"] = function()
    -- ================================================================
    -- Fivetone / movement_helper.lua
    -- 1:1 port of MovementHelper.kt adapted for NeoScripts 1.21.11 API
    -- Block classification: walk-through, stand-on, liquid, slab, stair
    -- ================================================================
    
    local MovementHelper = {}
    
    -- ── Block name sets for fast lookup ─────────────────────────────
    
    -- Blocks that are always passable (can walk through)
    local ALWAYS_PASSABLE = {
        ["minecraft:air"] = true, ["minecraft:cave_air"] = true, ["minecraft:void_air"] = true,
        ["minecraft:grass"] = true, ["minecraft:short_grass"] = true,
        ["minecraft:tall_grass"] = true, ["minecraft:fern"] = true,
        ["minecraft:large_fern"] = true, ["minecraft:dead_bush"] = true,
        ["minecraft:vine"] = true,
        ["minecraft:torch"] = true, ["minecraft:wall_torch"] = true,
        ["minecraft:soul_torch"] = true, ["minecraft:soul_wall_torch"] = true,
        ["minecraft:redstone_torch"] = true, ["minecraft:redstone_wall_torch"] = true,
        ["minecraft:string"] = true,
        ["minecraft:rail"] = true, ["minecraft:powered_rail"] = true,
        ["minecraft:detector_rail"] = true, ["minecraft:activator_rail"] = true,
        ["minecraft:wheat"] = true, ["minecraft:carrots"] = true,
        ["minecraft:potatoes"] = true, ["minecraft:beetroots"] = true,
        ["minecraft:sunflower"] = true, ["minecraft:lilac"] = true,
        ["minecraft:rose_bush"] = true, ["minecraft:peony"] = true,
        ["minecraft:nether_sprouts"] = true, ["minecraft:crimson_roots"] = true,
        ["minecraft:warped_roots"] = true,
        ["minecraft:dandelion"] = true, ["minecraft:poppy"] = true,
        ["minecraft:blue_orchid"] = true, ["minecraft:allium"] = true,
        ["minecraft:azure_bluet"] = true, ["minecraft:oxeye_daisy"] = true,
        ["minecraft:cornflower"] = true, ["minecraft:lily_of_the_valley"] = true,
        ["minecraft:wither_rose"] = false,  -- dangerous, handled separately
        ["minecraft:sugar_cane"] = true,
        ["minecraft:kelp"] = true, ["minecraft:kelp_plant"] = true,
        ["minecraft:seagrass"] = true, ["minecraft:tall_seagrass"] = true,
        ["minecraft:hanging_roots"] = true,
        ["minecraft:glow_lichen"] = true, ["minecraft:moss_carpet"] = true,
        ["minecraft:sculk_vein"] = true,
        ["minecraft:snow"] = true,  -- snow layer (1-layer) is passable, handled specially
    }
    
    -- Blocks that are NEVER passable (always block movement)
    local NEVER_PASSABLE = {
        ["minecraft:fire"] = true, ["minecraft:soul_fire"] = true,
        ["minecraft:tripwire"] = true,
        ["minecraft:cobweb"] = true,
        ["minecraft:end_portal"] = true,
        ["minecraft:cocoa"] = true,
        ["minecraft:iron_door"] = true,
    }
    
    -- Dangerous blocks to avoid walking into/onto
    local DANGEROUS = {
        ["minecraft:lava"] = true,
        ["minecraft:fire"] = true, ["minecraft:soul_fire"] = true,
        ["minecraft:cactus"] = true,
        ["minecraft:end_portal"] = true,
        ["minecraft:cobweb"] = true,
        ["minecraft:magma_block"] = true,
        ["minecraft:wither_rose"] = true,
        ["minecraft:sweet_berry_bush"] = true,
        ["minecraft:powder_snow"] = true,
    }
    
    -- Blocks that count as ladders
    local LADDER_BLOCKS = {
        ["minecraft:ladder"] = true,
        ["minecraft:vine"] = true,  -- vine can be climbed if backed by solid
    }
    
    -- Water block names
    local WATER_BLOCKS = {
        ["minecraft:water"] = true,
    }
    
    -- Lava block names
    local LAVA_BLOCKS = {
        ["minecraft:lava"] = true,
    }
    
    -- Slab blocks (partial list covering common ones)
    local SLAB_NAMES = {}
    -- We detect slabs by checking if the block name contains "slab"
    
    -- Stair blocks
    local STAIR_NAMES = {}
    -- We detect stairs by checking if the block name contains "stairs"
    
    -- ── Helper to get block safely ──────────────────────────────────
    
    local function getBlock(x, y, z)
        if not world.isBlockLoaded(x, y, z) then return nil end
        return world.getBlock(x, y, z)
    end
    
    local function getBlockState(x, y, z)
        if not world.isBlockLoaded(x, y, z) then return nil end
        return world.getBlockState(x, y, z)
    end
    
    -- ── Block type detection ────────────────────────────────────────
    
    --- Checks if a block name represents a slab.
    --- @param name string Block name
    --- @return boolean
    function MovementHelper.isSlab(name)
        return name and name:find("slab") ~= nil
    end
    
    --- Checks if a block name represents stairs.
    --- @param name string Block name
    --- @return boolean
    function MovementHelper.isStairs(name)
        return name and name:find("stairs") ~= nil
    end
    
    --- Checks if the block at (x,y,z) is a ladder.
    --- @param x number
    --- @param y number
    --- @param z number
    --- @return boolean
    function MovementHelper.isLadder(x, y, z)
        local b = getBlock(x, y, z)
        if not b then return false end
        return b.name == "minecraft:ladder"
    end
    
    --- Checks if a block is a ladder by examining its data.
    --- @param block table Block data from world.getBlock()
    --- @return boolean
    function MovementHelper.isLadderBlock(block)
        if not block then return false end
        return block.name == "minecraft:ladder"
    end
    
    --- Checks if block is water.
    --- @param block table Block data
    --- @return boolean
    function MovementHelper.isWater(block)
        if not block then return false end
        return WATER_BLOCKS[block.name] == true
    end
    
    --- Checks if block is lava.
    --- @param block table Block data
    --- @return boolean
    function MovementHelper.isLava(block)
        if not block then return false end
        return LAVA_BLOCKS[block.name] == true
    end
    
    --- Checks if block is any liquid.
    --- @param block table Block data
    --- @return boolean
    function MovementHelper.isLiquid(block)
        if not block then return false end
        return block.is_liquid == true
    end
    
    --- Checks if the block is a bottom slab (lower half).
    --- Uses block state properties.
    --- @param x number
    --- @param y number
    --- @param z number
    --- @return boolean
    function MovementHelper.isBottomSlab(x, y, z)
        local b = getBlockState(x, y, z)
        if not b then return false end
        if not MovementHelper.isSlab(b.name) then return false end
        -- In 1.21.11, slabs have a "type" property: "bottom", "top", or "double"
        -- We check via the block data if available
        if b.type and b.type == "bottom" then return true end
        -- Fallback: check collision box height
        local boxes = world.getCollisionBoxes(x, y, z, b)
        if boxes and #boxes > 0 then
            return boxes[1].maxY - boxes[1].minY <= 0.5625  -- 0.5 block + epsilon
        end
        return false
    end
    
    -- ── Core movement checks ────────────────────────────────────────
    
    --- Checks if the player can walk THROUGH a block at (x,y,z).
    --- Mirrors MovementHelper.canWalkThrough() from Kotlin.
    --- @param x number
    --- @param y number
    --- @param z number
    --- @return boolean
    function MovementHelper.canWalkThrough(x, y, z)
        local b = getBlock(x, y, z)
        if not b then return false end  -- unloaded = impassable
    
        local name = b.name
    
        -- Fast path: known passable
        if ALWAYS_PASSABLE[name] then return true end
    
        -- Fast path: known blockers
        if NEVER_PASSABLE[name] then return false end
    
        -- Dangerous blocks
        if DANGEROUS[name] then return false end
    
        -- Air check
        if b.is_air then return true end
    
        -- Liquid handling (mirrors Kotlin: still water at surface is OK, flowing is not)
        if b.is_liquid then
            if LAVA_BLOCKS[name] then return false end
            -- Only allow still water at the surface (no block above)
            local above = getBlock(x, y + 1, z)
            if above and (above.is_liquid or above.name == "minecraft:lily_pad") then
                return false
            end
            return WATER_BLOCKS[name] == true
        end
    
        -- Doors (non-iron) are passable (can be opened)
        if name and name:find("door") then
            if name == "minecraft:iron_door" then return false end
            return true
        end
    
        -- Fence gates are passable (can be opened)
        if name and name:find("fence_gate") then
            return true
        end
    
        -- Trapdoors are dangerous (can be in many states)
        if name and name:find("trapdoor") then
            return false
        end
    
        -- Default: use the block's is_solid property
        return not b.is_solid
    end
    
    --- Checks if the player can STAND ON the block at (x,y,z).
    --- Mirrors MovementHelper.canStandOn() from Kotlin.
    --- @param x number Floor block X
    --- @param y number Floor block Y
    --- @param z number Floor block Z
    --- @return boolean
    function MovementHelper.canStandOn(x, y, z)
        local b = getBlock(x, y, z)
        if not b then return false end
    
        local name = b.name
    
        -- Dangerous blocks: never stand on
        if DANGEROUS[name] then return false end
    
        -- Normal solid blocks
        if b.is_solid then return true end
    
        -- Special cases that are standable but not "solid" in MC's definition
        if name == "minecraft:ladder" then return true end
    
        -- Slabs are standable
        if MovementHelper.isSlab(name) then return true end
    
        -- Stairs are standable
        if MovementHelper.isStairs(name) then return true end
    
        -- Farmland, dirt path
        if name == "minecraft:farmland" or name == "minecraft:dirt_path" then return true end
    
        -- Glass
        if name and (name:find("glass") and not name:find("pane")) then return true end
    
        -- Chests, ender chests
        if name == "minecraft:chest" or name == "minecraft:ender_chest"
           or name == "minecraft:trapped_chest" then return true end
    
        -- Sea lantern
        if name == "minecraft:sea_lantern" then return true end
    
        -- Snow layers (thick enough)
        if name == "minecraft:snow" then
            if b.layers and b.layers >= 1 then return true end
        end
    
        -- Water + lily pad = standable
        if MovementHelper.isWater(b) then
            local above = getBlock(x, y + 1, z)
            if above and (above.name == "minecraft:lily_pad" or above.name == "minecraft:carpet"
                          or (above.name and above.name:find("carpet"))) then
                return true
            end
            return false
        end
    
        -- Lava: never
        if MovementHelper.isLava(b) then return false end
    
        return false
    end
    
    --- Checks if the player can stand at a feet position.
    --- Floor is at (x, feetY-1, z), feet at (x, feetY, z), head at (x, feetY+1, z).
    --- @param x number
    --- @param feetY number Y of player's feet
    --- @param z number
    --- @return boolean
    function MovementHelper.canStandAtFeet(x, feetY, z)
        if not MovementHelper.canStandOn(x, feetY - 1, z) then return false end
        if not MovementHelper.canWalkThrough(x, feetY, z) then return false end
        if not MovementHelper.canWalkThrough(x, feetY + 1, z) then return false end
        return true
    end
    
    --- Gets the max collision height of a block.
    --- Returns the maxY of the first collision box, or nil if none.
    --- @param x number
    --- @param y number
    --- @param z number
    --- @return number|nil maxY relative to block position
    function MovementHelper.getCollisionMaxY(x, y, z)
        local b = getBlock(x, y, z)
        if not b then return nil end
        local boxes = world.getCollisionBoxes(x, y, z, b)
        if not boxes or #boxes == 0 then return nil end
        -- maxY from collision boxes (these are absolute coordinates)
        local maxY = -math.huge
        for _, box in ipairs(boxes) do
            if box.maxY > maxY then maxY = box.maxY end
        end
        if maxY == -math.huge then return nil end
        return maxY
    end
    
    --- Checks if a block is dangerous to walk into.
    --- @param x number
    --- @param y number
    --- @param z number
    --- @return boolean
    function MovementHelper.avoidWalkingInto(x, y, z)
        local b = getBlock(x, y, z)
        if not b then return true end
        return DANGEROUS[b.name] == true
    end
    
    --- Checks if a ladder can be entered from a given direction.
    --- A ladder blocks movement from the direction it's attached to.
    --- @param x number Ladder X
    --- @param y number Ladder Y
    --- @param z number Ladder Z
    --- @param dx number Direction delta X (from source to ladder)
    --- @param dz number Direction delta Z (from source to ladder)
    --- @return boolean true if can walk into the ladder from this direction
    function MovementHelper.canWalkIntoLadder(x, y, z, dx, dz)
        local b = getBlockState(x, y, z)
        if not b then return false end
        if b.name ~= "minecraft:ladder" then return false end
        -- Ladder facing determines which direction blocks entry
        -- If ladder faces NORTH, it's on the south side of a block,
        -- and you can't enter from the NORTH (dx=0,dz=-1)
        local facing = b.facing
        if not facing then return true end  -- unknown = allow
        -- Block entry from the direction the ladder faces
        if facing == "north" and dx == 0 and dz == -1 then return false end
        if facing == "south" and dx == 0 and dz == 1  then return false end
        if facing == "west"  and dx == -1 and dz == 0 then return false end
        if facing == "east"  and dx == 1  and dz == 0 then return false end
        return true
    end
    
    return MovementHelper
    
end

__bundle_preload["libs/fivetone/goals"] = function()
    -- ================================================================
    -- Fivetone / goals.lua
    -- 1:1 port of Goal.kt / IGoal.kt + extended goal types
    -- ================================================================
    
    local Goals = {}
    
    local SQRT_2 = math.sqrt(2.0)
    
    --- GoalBlock: reach exact X, Y, Z position.
    --- Heuristic uses octile distance + asymmetric vertical weighting
    --- matching the Kotlin Goal.kt exactly.
    --- @param goalX number
    --- @param goalY number
    --- @param goalZ number
    --- @param costs table ActionCosts instance (for cost constants)
    --- @return table Goal object
    function Goals.block(goalX, goalY, goalZ, costs)
        goalX = math.floor(goalX)
        goalY = math.floor(goalY)
        goalZ = math.floor(goalZ)
    
        return {
            type = "block",
            x = goalX, y = goalY, z = goalZ,
    
            isAtGoal = function(self, x, y, z)
                return goalX == x and goalY == y and goalZ == z
            end,
    
            heuristic = function(self, x, y, z)
                local dx = math.abs(goalX - x)
                local dz = math.abs(goalZ - z)
                local straight = math.abs(dx - dz)
                local vertical = math.abs(goalY - y)
                local diagonal = math.min(dx, dz)
    
                -- Asymmetric vertical cost: going UP is much more expensive than falling
                if goalY > y then
                    -- Exact constant from Kotlin source: 6.234399666206506
                    vertical = vertical * 6.234399666206506
                else
                    vertical = vertical * costs.N_BLOCK_FALL_COST[2] / 2.0
                end
    
                return (straight + diagonal * SQRT_2) * costs.ONE_BLOCK_SPRINT_COST + vertical
            end,
    
            desc = function(self)
                return goalX .. " " .. goalY .. " " .. goalZ
            end,
        }
    end
    
    --- GoalXZ: reach a column at any Y level.
    --- @param goalX number
    --- @param goalZ number
    --- @param costs table ActionCosts instance
    --- @return table Goal object
    function Goals.xz(goalX, goalZ, costs)
        goalX = math.floor(goalX)
        goalZ = math.floor(goalZ)
    
        return {
            type = "xz",
            x = goalX, z = goalZ,
    
            isAtGoal = function(self, x, y, z)
                return goalX == x and goalZ == z
            end,
    
            heuristic = function(self, x, y, z)
                local dx = math.abs(goalX - x)
                local dz = math.abs(goalZ - z)
                local straight = math.abs(dx - dz)
                local diagonal = math.min(dx, dz)
                return (straight + diagonal * SQRT_2) * costs.ONE_BLOCK_SPRINT_COST
            end,
    
            desc = function(self)
                return "XZ " .. goalX .. " " .. goalZ
            end,
        }
    end
    
    --- GoalYLevel: reach a specific Y altitude at any XZ.
    --- @param goalY number
    --- @param costs table ActionCosts instance
    --- @return table Goal object
    function Goals.yLevel(goalY, costs)
        goalY = math.floor(goalY)
    
        return {
            type = "ylevel",
            y = goalY,
    
            isAtGoal = function(self, x, y, z)
                return y == goalY
            end,
    
            heuristic = function(self, x, y, z)
                return math.abs(goalY - y) * costs.ONE_BLOCK_SPRINT_COST
            end,
    
            desc = function(self)
                return "Y=" .. goalY
            end,
        }
    end
    
    --- GoalNear: get within `range` blocks of a point.
    --- @param goalX number
    --- @param goalY number
    --- @param goalZ number
    --- @param range number Radius in blocks
    --- @param costs table ActionCosts instance
    --- @return table Goal object
    function Goals.near(goalX, goalY, goalZ, range, costs)
        goalX = math.floor(goalX)
        goalY = math.floor(goalY)
        goalZ = math.floor(goalZ)
        local rsq = range * range
    
        return {
            type = "near",
            x = goalX, y = goalY, z = goalZ, range = range,
    
            isAtGoal = function(self, x, y, z)
                local dx, dy, dz = x - goalX, y - goalY, z - goalZ
                return dx * dx + dy * dy + dz * dz <= rsq
            end,
    
            heuristic = function(self, x, y, z)
                local dx = math.abs(goalX - x)
                local dz = math.abs(goalZ - z)
                local straight = math.abs(dx - dz)
                local diagonal = math.min(dx, dz)
                local dist = (straight + diagonal * SQRT_2) * costs.ONE_BLOCK_SPRINT_COST
                local vertDist = math.abs(goalY - y) * costs.ONE_BLOCK_SPRINT_COST
                -- Subtract range from heuristic (admissible)
                return math.max(0, dist + vertDist - range * costs.ONE_BLOCK_SPRINT_COST)
            end,
    
            desc = function(self)
                return "Near " .. goalX .. " " .. goalY .. " " .. goalZ .. " r=" .. range
            end,
        }
    end
    
    --- GoalRunAway: get at least `dist` blocks away from a point.
    --- @param goalX number Origin X
    --- @param goalZ number Origin Z
    --- @param dist number Minimum distance
    --- @param costs table ActionCosts instance
    --- @return table Goal object
    function Goals.runAway(goalX, goalZ, dist, costs)
        goalX = math.floor(goalX)
        goalZ = math.floor(goalZ)
        local dsq = dist * dist
    
        return {
            type = "runaway",
            x = goalX, z = goalZ, dist = dist,
    
            isAtGoal = function(self, x, y, z)
                local dx, dz = x - goalX, z - goalZ
                return dx * dx + dz * dz >= dsq
            end,
    
            heuristic = function(self, x, y, z)
                local dx, dz = x - goalX, z - goalZ
                local curSq = dx * dx + dz * dz
                if curSq >= dsq then return 0 end
                return (dist - math.sqrt(curSq)) * costs.ONE_BLOCK_SPRINT_COST
            end,
    
            desc = function(self)
                return "RunAway " .. goalX .. " " .. goalZ .. " d=" .. dist
            end,
        }
    end
    
    return Goals
    
end

__bundle_preload["libs/fivetone/movements/traverse"] = function()
    -- ================================================================
    -- Fivetone / movements/traverse.lua
    -- 1:1 port of MovementTraverse.kt
    -- Flat walk in 4 cardinal directions with collision height checks
    -- ================================================================
    
    local MH = __bundle_require("libs/fivetone/movement_helper")
    
    local Traverse = {}
    
    --- Calculates the cost of traversing (flat walk) from (x,y,z) to (destX,y,destZ).
    --- @param costs table ActionCosts instance
    --- @param x number Source X
    --- @param y number Source Y (feet level)
    --- @param z number Source Z
    --- @param destX number Destination X
    --- @param destZ number Destination Z
    --- @param res table MovementResult to write into
    function Traverse.calculateCost(costs, x, y, z, destX, destZ, res)
        res:set(destX, y, destZ)
    
        -- Floor at destination must be standable
        if not MH.canStandOn(destX, y - 1, destZ) then return end
    
        -- Feet and head clearance at destination
        if not MH.canWalkThrough(destX, y, destZ) then return end
        if not MH.canWalkThrough(destX, y + 1, destZ) then return end
    
        -- Ladder checks: can't traverse into/from a ladder in the wrong direction
        local dx = destX - x
        local dz = destZ - z
    
        -- Check source feet level for ladder
        if MH.isLadder(x, y, z) then
            if not MH.canWalkIntoLadder(x, y, z, -dx, -dz) then
                res.cost = costs.INF_COST
                return
            end
        end
    
        -- Check dest feet level for ladder
        if MH.isLadder(destX, y, destZ) then
            if not MH.canWalkIntoLadder(destX, y, destZ, dx, dz) then
                res.cost = costs.INF_COST
                return
            end
        end
    
        -- Get collision heights to determine if we need to jump over height diff
        local sourceMaxY = MH.getCollisionMaxY(x, y - 1, z)
        local destMaxY   = MH.getCollisionMaxY(destX, y - 1, destZ)
    
        if not sourceMaxY or not destMaxY then
            -- Fallback: assume flat sprint
            res.cost = costs.ONE_BLOCK_SPRINT_COST
            return
        end
    
        local diff = destMaxY - sourceMaxY
    
        if diff <= 0.5 then
            -- Small height difference: normal sprint
            res.cost = costs.ONE_BLOCK_SPRINT_COST
        elseif diff <= 1.0 then
            -- Need to jump (e.g., slab to full block)
            res.cost = costs.JUMP_ONE_BLOCK_COST
        else
            -- Too high to traverse
            res.cost = costs.INF_COST
        end
    end
    
    return Traverse
    
end

__bundle_preload["libs/fivetone/movements/ascend"] = function()
    -- ================================================================
    -- Fivetone / movements/ascend.lua
    -- 1:1 port of MovementAscend.kt
    -- Step up one block in 4 cardinal directions
    -- ================================================================
    
    local MH = __bundle_require("libs/fivetone/movement_helper")
    
    local Ascend = {}
    
    --- Calculates the cost of ascending from (x,y,z) to (destX, y+1, destZ).
    --- @param costs table ActionCosts instance
    --- @param x number Source X
    --- @param y number Source Y (feet level)
    --- @param z number Source Z
    --- @param destX number Destination X
    --- @param destZ number Destination Z
    --- @param res table MovementResult to write into
    function Ascend.calculateCost(costs, x, y, z, destX, destZ, res)
        res:set(destX, y + 1, destZ)
    
        -- Destination floor (y+1-1 = y) must be standable — this IS the step block
        -- But actually for ascend, the new floor is at y, and feet at y+1
        -- So we need canStandOn at (destX, y, destZ) — the block we step onto
        if not MH.canStandOn(destX, y, destZ) then return end
    
        -- Head clearance above destination: y+2, y+3 must be passable
        if not MH.canWalkThrough(destX, y + 1, destZ) then return end
        if not MH.canWalkThrough(destX, y + 2, destZ) then return end
    
        -- Head clearance above source for the jump: y+2 must be passable
        if not MH.canWalkThrough(x, y + 2, z) then return end
    
        -- Ladder checks
        local srcBlock = MH.isLadder(x, y - 1, z)
        if srcBlock then return end  -- Can't ascend from a ladder
    
        if MH.isLadder(destX, y, destZ) then
            local dx = destX - x
            local dz = destZ - z
            if not MH.canWalkIntoLadder(destX, y, destZ, dx, dz) then
                return
            end
        end
    
        -- Collision height comparison for cost determination
        local sourceMaxY = MH.getCollisionMaxY(x, y - 1, z)
        local destMaxY   = MH.getCollisionMaxY(destX, y, destZ)
    
        if not sourceMaxY or not destMaxY then
            -- Fallback: assume jump cost
            res.cost = costs.JUMP_ONE_BLOCK_COST
            return
        end
    
        local diff = destMaxY - sourceMaxY
    
        if diff <= 0.5 then
            -- Small step (e.g., slab to slab at different Y)
            res.cost = costs.ONE_BLOCK_SPRINT_COST
        elseif diff <= 1.125 then
            -- Normal jump up
            res.cost = costs.JUMP_ONE_BLOCK_COST
        else
            -- Too high
            res.cost = costs.INF_COST
        end
    end
    
    return Ascend
    
end

__bundle_preload["libs/fivetone/movements/descend"] = function()
    -- ================================================================
    -- Fivetone / movements/descend.lua
    -- 1:1 port of MovementDescend.kt
    -- Walk-off + freefall with ladder/water landing support
    -- ================================================================
    
    local MH = __bundle_require("libs/fivetone/movement_helper")
    
    local Descend = {}
    
    --- Calculates the cost of descending from (x,y,z) to (destX, y-1, destZ).
    --- If no immediate floor, tries freefall up to maxFallHeight.
    --- @param costs table ActionCosts instance
    --- @param x number Source X
    --- @param y number Source Y (feet level)
    --- @param z number Source Z
    --- @param destX number Destination X
    --- @param destZ number Destination Z
    --- @param res table MovementResult to write into
    --- @param maxFallHeight number Maximum safe fall height (default 20)
    function Descend.calculateCost(costs, x, y, z, destX, destZ, res, maxFallHeight)
        maxFallHeight = maxFallHeight or 20
        res:set(destX, y - 1, destZ)
    
        -- Clearance at destination column: y+1, y, y-1 level passability
        -- We need to walk into (destX, y, destZ) and (destX, y+1, destZ)
        if not MH.canWalkThrough(destX, y + 1, destZ) then return end
        if not MH.canWalkThrough(destX, y, destZ) then return end
    
        -- Can't descend from/to a ladder
        if MH.isLadder(x, y - 1, z) then return end
        if MH.isLadder(destX, y, destZ) then return end
    
        -- Check immediate floor one block down
        local canStandBelow = MH.canStandOn(destX, y - 2, destZ)
        local belowIsLadder = MH.isLadder(destX, y - 2, destZ)
    
        if not canStandBelow or belowIsLadder then
            -- No immediate floor — try freefall
            -- First, the block at dest y-1 must be passable to fall through
            if not MH.canWalkThrough(destX, y - 1, destZ) then return end
            Descend._freeFallCost(costs, x, y, z, destX, destZ, res, maxFallHeight)
            return
        end
    
        -- Normal 1-block descend: check destination feet passability
        if not MH.canWalkThrough(destX, y - 1, destZ) then return end
    
        -- Collision height comparison
        local sourceMaxY = MH.getCollisionMaxY(x, y - 1, z)
        local destMaxY   = MH.getCollisionMaxY(destX, y - 2, destZ)
    
        if not sourceMaxY or not destMaxY then
            -- Fallback
            res.cost = costs.WALK_OFF_ONE_BLOCK_COST * costs.SPRINT_MULTIPLIER + costs.N_BLOCK_FALL_COST[1]
            return
        end
    
        local diff = sourceMaxY - destMaxY
    
        if diff <= 0.5 then
            -- Small step down (e.g., full block to slab)
            res.cost = costs.ONE_BLOCK_WALK_COST
        elseif diff <= 1.125 then
            -- Normal 1-block drop
            res.cost = costs.WALK_OFF_ONE_BLOCK_COST * costs.SPRINT_MULTIPLIER + costs.N_BLOCK_FALL_COST[1]
        else
            res.cost = costs.INF_COST
        end
    end
    
    --- Calculates freefall cost when there's no immediate floor below.
    --- Scans downward for a landing surface, supporting water and ladder breaks.
    --- @param costs table ActionCosts instance
    --- @param x number Source X
    --- @param y number Source Y (feet level)
    --- @param z number Source Z
    --- @param destX number Destination X
    --- @param destZ number Destination Z
    --- @param res table MovementResult to write into
    --- @param maxFallHeight number Maximum fall distance
    function Descend._freeFallCost(costs, x, y, z, destX, destZ, res, maxFallHeight)
        local effStartHeight = y  -- effective start for ladder cost reduction
        local extraCost = 0
    
        for fellSoFar = 2, 256 do
            local newY = y - fellSoFar
            if newY < -64 then return end  -- below world
    
            local blockOntoPassable = MH.canWalkThrough(destX, newY, destZ)
            local unprotectedFallHeight = fellSoFar - (y - effStartHeight)
    
            -- Safety: don't index beyond fall cost table
            if unprotectedFallHeight > 256 then return end
    
            local costUpUntilThisBlock = costs.WALK_OFF_ONE_BLOCK_COST
                + (costs.N_BLOCK_FALL_COST[unprotectedFallHeight] or costs.INF_COST)
                + extraCost
    
            if costUpUntilThisBlock >= costs.INF_COST then return end
    
            -- Check if we can land here
            if MH.canStandOn(destX, newY, destZ) then
                -- Check for ladder at landing (reduces fall damage effectively)
                if unprotectedFallHeight <= 11 and MH.isLadder(destX, newY, destZ) then
                    extraCost = extraCost
                        + (costs.N_BLOCK_FALL_COST[unprotectedFallHeight - 1] or 0)
                        + costs.ONE_DOWN_LADDER_COST
                    effStartHeight = newY
                    -- Continue scanning further down
                elseif fellSoFar <= maxFallHeight then
                    -- Valid landing within safe fall height
                    res.y = newY + 1  -- feet position is one above floor
                    res.cost = costUpUntilThisBlock
                    return
                else
                    return  -- too far to fall
                end
            else
                -- Not standable — check if water (safe landing)
                local landBlock = world.getBlock(destX, newY, destZ)
                if landBlock and MH.isWater(landBlock) then
                    -- Water breaks fall — check if there's solid below water
                    if MH.canStandOn(destX, newY - 1, destZ) then
                        res.y = newY  -- land in water
                        res.cost = costUpUntilThisBlock
                        return
                    end
                    return  -- deep water, can't guarantee landing
                end
    
                -- Can we fall through this block?
                if not blockOntoPassable then
                    return  -- blocked
                end
                -- Continue falling
            end
        end
    end
    
    return Descend
    
end

__bundle_preload["libs/fivetone/movements/diagonal"] = function()
    -- ================================================================
    -- Fivetone / movements/diagonal.lua
    -- 1:1 port of MovementDiagonal.kt
    -- Diagonal move with ascend/descend variants + corner-clip prevention
    -- ================================================================
    
    local MH = __bundle_require("libs/fivetone/movement_helper")
    
    local Diagonal = {}
    
    local SQRT_2 = math.sqrt(2.0)
    
    --- Calculates the cost of moving diagonally from (x,y,z) to (destX,?,destZ).
    --- Supports same-level, ascending (+1), and descending (-1) diagonals.
    --- @param costs table ActionCosts instance
    --- @param x number Source X
    --- @param y number Source Y (feet level)
    --- @param z number Source Z
    --- @param destX number Destination X
    --- @param destZ number Destination Z
    --- @param res table MovementResult to write into
    function Diagonal.calculateCost(costs, x, y, z, destX, destZ, res)
        res:set(destX, y, destZ)
    
        -- Head clearance at diagonal destination
        if not MH.canWalkThrough(destX, y + 1, destZ) then return end
    
        local ascend = false
        local descend = false
    
        -- Check feet level at destination
        if not MH.canWalkThrough(destX, y, destZ) then
            -- Feet blocked → try ascending (diagonal + up)
            ascend = true
            -- Need extra head room above source
            if not MH.canWalkThrough(x, y + 2, z) then return end
            -- Dest block at y must be standable (it's the new floor)
            if not MH.canStandOn(destX, y, destZ) then return end
            -- Head clearance above ascended position
            if not MH.canWalkThrough(destX, y + 1, destZ) then return end
            res.y = y + 1
        else
            -- Feet passable — check floor
            if not MH.canStandOn(destX, y - 1, destZ) then
                -- No floor → try descending (diagonal + down)
                descend = true
                if not MH.canStandOn(destX, y - 2, destZ) then return end
                if not MH.canWalkThrough(destX, y - 1, destZ) then return end
                res.y = y - 1
            end
        end
    
        -- ── Corner-clip prevention ──────────────────────────────────
        -- Both intermediate cardinal positions must be fully passable
        -- at feet, head, and above-head levels
        local dx = destX - x
        local dz = destZ - z
    
        -- Intermediate A: same X, diagonal Z
        local aTopOk  = MH.canWalkThrough(x, y + 2, z + dz)
        local aMidOk  = MH.canWalkThrough(x, y + 1, z + dz)
        local aLowOk  = MH.canWalkThrough(x, y, z + dz)
    
        -- Intermediate B: diagonal X, same Z
        local bTopOk  = MH.canWalkThrough(x + dx, y + 2, z)
        local bMidOk  = MH.canWalkThrough(x + dx, y + 1, z)
        local bLowOk  = MH.canWalkThrough(x + dx, y, z)
    
        if not (aTopOk and aMidOk and aLowOk and bTopOk and bMidOk and bLowOk) then
            return  -- corner clip would occur
        end
    
        -- ── Cost calculation ────────────────────────────────────────
    
        -- Ladder at source blocks diagonal movement
        if MH.isLadder(x, y - 1, z) then return end
    
        -- Base cost
        local cost = costs.ONE_BLOCK_WALK_COST
    
        -- Water penalty
        local aboveSrc = world.getBlock(x, y, z)
        if aboveSrc and MH.isWater(aboveSrc) then
            if ascend then return end  -- can't ascend diagonally in water
            cost = costs.ONE_BLOCK_WALK_IN_WATER_COST * SQRT_2
        else
            cost = cost * costs.SPRINT_MULTIPLIER
        end
    
        -- Final cost based on movement type
        if not ascend and not descend then
            -- Flat diagonal
            res.cost = cost * SQRT_2
            return
        end
    
        -- Height-aware cost for ascend/descend diagonal
        local sourceMaxY = MH.getCollisionMaxY(x, y - 1, z) or y
        
        if ascend then
            local destMaxY = MH.getCollisionMaxY(destX, y, destZ) or (y + 1)
            local diff = destMaxY - sourceMaxY
            if diff <= 0.5 then
                res.cost = cost * SQRT_2
            elseif diff <= 1.125 then
                res.cost = cost * SQRT_2 + costs.JUMP_ONE_BLOCK_COST
            else
                res.cost = costs.INF_COST
            end
            return
        end
    
        if descend then
            local destMaxY = MH.getCollisionMaxY(destX, y - 2, destZ) or (y - 1)
            local diff = sourceMaxY - destMaxY
            if diff <= 0.5 then
                res.cost = cost * SQRT_2
            elseif diff <= 1.0 then
                res.cost = costs.N_BLOCK_FALL_COST[1] + cost * SQRT_2
            else
                res.cost = costs.INF_COST
            end
        end
    end
    
    return Diagonal
    
end

__bundle_preload["libs/fivetone/moves"] = function()
    -- ================================================================
    -- Fivetone / moves.lua
    -- 1:1 port of Moves.kt
    -- 16-direction move table: 4 traverse, 4 ascend, 4 descend, 4 diagonal
    -- ================================================================
    
    local Traverse = __bundle_require("libs/fivetone/movements/traverse")
    local Ascend   = __bundle_require("libs/fivetone/movements/ascend")
    local Descend  = __bundle_require("libs/fivetone/movements/descend")
    local Diagonal = __bundle_require("libs/fivetone/movements/diagonal")
    
    --- Each move entry: { name, offsetX, offsetZ, calculate(costs, x, y, z, res, maxFall) }
    --- The calculate function writes destination and cost into res.
    local Moves = {
        -- ── TRAVERSE (flat walk, 4 cardinal) ────────────────────────
        {
            name = "TRAVERSE_NORTH", offsetX = 0, offsetZ = -1,
            calculate = function(costs, x, y, z, res, maxFall)
                Traverse.calculateCost(costs, x, y, z, x + 0, z + -1, res)
            end,
        },
        {
            name = "TRAVERSE_SOUTH", offsetX = 0, offsetZ = 1,
            calculate = function(costs, x, y, z, res, maxFall)
                Traverse.calculateCost(costs, x, y, z, x + 0, z + 1, res)
            end,
        },
        {
            name = "TRAVERSE_EAST", offsetX = 1, offsetZ = 0,
            calculate = function(costs, x, y, z, res, maxFall)
                Traverse.calculateCost(costs, x, y, z, x + 1, z + 0, res)
            end,
        },
        {
            name = "TRAVERSE_WEST", offsetX = -1, offsetZ = 0,
            calculate = function(costs, x, y, z, res, maxFall)
                Traverse.calculateCost(costs, x, y, z, x + -1, z + 0, res)
            end,
        },
    
        -- ── ASCEND (step up +1, 4 cardinal) ─────────────────────────
        {
            name = "ASCEND_NORTH", offsetX = 0, offsetZ = -1,
            calculate = function(costs, x, y, z, res, maxFall)
                Ascend.calculateCost(costs, x, y, z, x + 0, z + -1, res)
            end,
        },
        {
            name = "ASCEND_SOUTH", offsetX = 0, offsetZ = 1,
            calculate = function(costs, x, y, z, res, maxFall)
                Ascend.calculateCost(costs, x, y, z, x + 0, z + 1, res)
            end,
        },
        {
            name = "ASCEND_EAST", offsetX = 1, offsetZ = 0,
            calculate = function(costs, x, y, z, res, maxFall)
                Ascend.calculateCost(costs, x, y, z, x + 1, z + 0, res)
            end,
        },
        {
            name = "ASCEND_WEST", offsetX = -1, offsetZ = 0,
            calculate = function(costs, x, y, z, res, maxFall)
                Ascend.calculateCost(costs, x, y, z, x + -1, z + 0, res)
            end,
        },
    
        -- ── DESCEND (step/fall down, 4 cardinal) ────────────────────
        {
            name = "DESCEND_NORTH", offsetX = 0, offsetZ = -1,
            calculate = function(costs, x, y, z, res, maxFall)
                Descend.calculateCost(costs, x, y, z, x + 0, z + -1, res, maxFall)
            end,
        },
        {
            name = "DESCEND_SOUTH", offsetX = 0, offsetZ = 1,
            calculate = function(costs, x, y, z, res, maxFall)
                Descend.calculateCost(costs, x, y, z, x + 0, z + 1, res, maxFall)
            end,
        },
        {
            name = "DESCEND_EAST", offsetX = 1, offsetZ = 0,
            calculate = function(costs, x, y, z, res, maxFall)
                Descend.calculateCost(costs, x, y, z, x + 1, z + 0, res, maxFall)
            end,
        },
        {
            name = "DESCEND_WEST", offsetX = -1, offsetZ = 0,
            calculate = function(costs, x, y, z, res, maxFall)
                Descend.calculateCost(costs, x, y, z, x + -1, z + 0, res, maxFall)
            end,
        },
    
        -- ── DIAGONAL (4 diagonal directions) ────────────────────────
        {
            name = "DIAGONAL_NE", offsetX = 1, offsetZ = -1,
            calculate = function(costs, x, y, z, res, maxFall)
                Diagonal.calculateCost(costs, x, y, z, x + 1, z + -1, res)
            end,
        },
        {
            name = "DIAGONAL_NW", offsetX = -1, offsetZ = -1,
            calculate = function(costs, x, y, z, res, maxFall)
                Diagonal.calculateCost(costs, x, y, z, x + -1, z + -1, res)
            end,
        },
        {
            name = "DIAGONAL_SE", offsetX = 1, offsetZ = 1,
            calculate = function(costs, x, y, z, res, maxFall)
                Diagonal.calculateCost(costs, x, y, z, x + 1, z + 1, res)
            end,
        },
        {
            name = "DIAGONAL_SW", offsetX = -1, offsetZ = 1,
            calculate = function(costs, x, y, z, res, maxFall)
                Diagonal.calculateCost(costs, x, y, z, x + -1, z + 1, res)
            end,
        },
    }
    
    return Moves
    
end

__bundle_preload["libs/fivetone/block_util"] = function()
    -- ================================================================
    -- Fivetone / block_util.lua
    -- 1:1 port of BlockUtil.kt
    -- Bresenham 3D line-of-sight for path smoothing
    -- ================================================================
    
    local MH = __bundle_require("libs/fivetone/movement_helper")
    
    local BlockUtil = {}
    
    --- 3D Bresenham line-of-sight check between two block positions.
    --- Returns true if every block along the line is walkable.
    --- Used for path smoothing (removing unnecessary waypoints).
    --- @param startX number Start X
    --- @param startY number Start Y
    --- @param startZ number Start Z
    --- @param endX number End X
    --- @param endY number End Y
    --- @param endZ number End Z
    --- @return boolean true if line of sight is clear (all blocks walkable)
    function BlockUtil.bresenham(startX, startY, startZ, endX, endY, endZ)
        -- Ray from center of start to center of end
        local sx = startX + 0.5
        local sy = startY + 0.5
        local sz = startZ + 0.5
        local ex = endX + 0.5
        local ey = endY + 0.5
        local ez = endZ + 0.5
    
        local x0 = math.floor(sx)
        local y0 = math.floor(sy)
        local z0 = math.floor(sz)
        local x1 = math.floor(ex)
        local y1 = math.floor(ey)
        local z1 = math.floor(ez)
    
        local iterations = 200
    
        while iterations > 0 do
            iterations = iterations - 1
    
            if x0 == x1 and y0 == y1 and z0 == z1 then
                return true  -- reached destination
            end
    
            local hasNewX, hasNewY, hasNewZ = true, true, true
            local newX, newY, newZ = 999.0, 999.0, 999.0
    
            if x1 > x0 then
                newX = x0 + 1.0
            elseif x1 < x0 then
                newX = x0 + 0.0
            else
                hasNewX = false
            end
    
            if y1 > y0 then
                newY = y0 + 1.0
            elseif y1 < y0 then
                newY = y0 + 0.0
            else
                hasNewY = false
            end
    
            if z1 > z0 then
                newZ = z0 + 1.0
            elseif z1 < z0 then
                newZ = z0 + 0.0
            else
                hasNewZ = false
            end
    
            local stepX, stepY, stepZ = 999.0, 999.0, 999.0
            local dx = ex - sx
            local dy = ey - sy
            local dz = ez - sz
    
            if hasNewX then stepX = (newX - sx) / dx end
            if hasNewY then stepY = (newY - sy) / dy end
            if hasNewZ then stepZ = (newZ - sz) / dz end
    
            if stepX == -0.0 then stepX = -1.0e-4 end
            if stepY == -0.0 then stepY = -1.0e-4 end
            if stepZ == -0.0 then stepZ = -1.0e-4 end
    
            local face  -- direction we crossed
    
            if stepX < stepY and stepX < stepZ then
                face = (x1 > x0) and "west" or "east"
                sx = newX
                sy = sy + dy * stepX
                sz = sz + dz * stepX
            elseif stepY < stepZ then
                face = (y1 > y0) and "down" or "up"
                sx = sx + dx * stepY
                sy = newY
                sz = sz + dz * stepY
            else
                face = (z1 > z0) and "north" or "south"
                sx = sx + dx * stepZ
                sy = sy + dy * stepZ
                sz = newZ
            end
    
            x0 = math.floor(sx) - (face == "east"  and 1 or 0)
            y0 = math.floor(sy) - (face == "up"    and 1 or 0)
            z0 = math.floor(sz) - (face == "south" and 1 or 0)
    
            -- Validate this position: must be standable with head clearance
            if not MH.canStandOn(x0, y0, z0) then
                -- Try vertical scan ±3 for a valid block
                local found = false
                for i = -3, 3 do
                    if i == 0 then goto skipZero end
                    if MH.canStandOn(x0, y0 + i, z0)
                       and MH.canWalkThrough(x0, y0 + i + 1, z0)
                       and MH.canWalkThrough(x0, y0 + i + 2, z0) then
                        -- Check the height delta is reasonable
                        if math.abs(i) <= 1 then
                            y0 = y0 + i
                            found = true
                            break
                        end
                    end
                    ::skipZero::
                end
                if not found then return false end
            else
                -- Verify head clearance
                if not MH.canWalkThrough(x0, y0 + 1, z0) then return false end
                if not MH.canWalkThrough(x0, y0 + 2, z0) then return false end
            end
        end
    
        return false  -- ran out of iterations
    end
    
    --- Smooths a path by removing unnecessary waypoints using line-of-sight.
    --- @param path table Array of {x, y, z} waypoints
    --- @return table Smoothed array of {x, y, z} waypoints
    function BlockUtil.smoothPath(path)
        if not path or #path <= 2 then return path end
    
        local smooth = {}
        smooth[1] = path[1]
        local currPoint = 1
    
        while currPoint + 1 <= #path do
            local nextPos = currPoint + 1
    
            -- Greedy: try to skip as many waypoints as possible
            for i = #path, nextPos + 1, -1 do
                if BlockUtil.bresenham(
                    path[currPoint].x, path[currPoint].y, path[currPoint].z,
                    path[i].x, path[i].y, path[i].z
                ) then
                    nextPos = i
                    break
                end
            end
    
            smooth[#smooth + 1] = path[nextPos]
            currPoint = nextPos
        end
    
        return smooth
    end
    
    return BlockUtil
    
end

__bundle_preload["libs/fivetone/path"] = function()
    -- ================================================================
    -- Fivetone / path.lua
    -- 1:1 port of Path.kt
    -- Path reconstruction + smoothing wrapper
    -- ================================================================
    
    local BlockUtil = __bundle_require("libs/fivetone/block_util")
    
    local Path = {}
    Path.__index = Path
    
    --- Creates a new Path from start/end waypoint arrays.
    --- @param waypoints table Array of {x, y, z} from A* reconstruction
    --- @param isComplete boolean Whether the path reaches the goal
    --- @param nodesExplored number Number of nodes explored during A*
    --- @return table Path instance
    function Path.new(waypoints, isComplete, nodesExplored)
        local self = setmetatable({}, Path)
        self.waypoints     = waypoints or {}
        self.isComplete    = isComplete or false
        self.nodesExplored = nodesExplored or 0
        self.smoothedPath  = nil
        return self
    end
    
    --- Returns the raw (unsmoothed) waypoints.
    --- @return table Array of {x, y, z}
    function Path:getRawPath()
        return self.waypoints
    end
    
    --- Returns a smoothed path using Bresenham line-of-sight.
    --- Caches the result for repeated calls.
    --- @return table Smoothed array of {x, y, z}
    function Path:getSmoothedPath()
        if self.smoothedPath then return self.smoothedPath end
        self.smoothedPath = BlockUtil.smoothPath(self.waypoints)
        return self.smoothedPath
    end
    
    --- Returns the number of waypoints.
    --- @return number
    function Path:length()
        return #self.waypoints
    end
    
    --- Returns a specific waypoint.
    --- @param idx number 1-indexed
    --- @return table {x, y, z}
    function Path:getWaypoint(idx)
        return self.waypoints[idx]
    end
    
    --- Returns the start position.
    --- @return table {x, y, z}
    function Path:getStart()
        return self.waypoints[1]
    end
    
    --- Returns the end position.
    --- @return table {x, y, z}
    function Path:getEnd()
        return self.waypoints[#self.waypoints]
    end
    
    return Path
    
end

__bundle_preload["libs/fivetone/path_executor"] = function()
    -- ================================================================
    -- Fivetone / path_executor.lua
    -- Humanized path walker — ALL real player inputs
    -- Uses setSilentRotation with movementCorrection for legit movement
    -- Gaussian-jittered timing, smooth rotation curves, real W/Jump/Sprint
    -- ================================================================
    
    local MH = __bundle_require("libs/fivetone/movement_helper")
    
    local Executor = {}
    Executor.__index = Executor
    
    -- ── Humanization constants ──────────────────────────────────────
    
    -- Gaussian random: Box-Muller transform for human-like jitter
    local function gaussRandom(mean, stddev)
        local u1 = math.random()
        local u2 = math.random()
        -- Clamp u1 away from 0 to avoid log(0)
        if u1 < 1e-10 then u1 = 1e-10 end
        local z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
        return mean + z * stddev
    end
    
    -- Clamp utility
    local function clamp(val, lo, hi)
        if val < lo then return lo end
        if val > hi then return hi end
        return val
    end
    
    --- Creates a new path executor.
    --- @param config table Configuration table
    --- @return table Executor instance
    function Executor.new(config)
        local self = setmetatable({}, Executor)
    
        self.config = config or {}
    
        -- ── Humanization settings ───────────────────────────────────
        -- Arrive distance (how close to a waypoint before advancing)
        -- Slightly randomized per waypoint to look human
        self.arriveDist    = self.config.arriveDist    or 0.35
        self.arriveJitter  = self.config.arriveJitter  or 0.08  -- ± jitter on arrive dist
    
        -- Lookahead: how many waypoints ahead to steer toward
        self.lookahead     = self.config.lookahead     or 4
    
        -- Stuck detection
        self.stuckTicks    = self.config.stuckTicks    or 60
        self.stuckThreshSq = 0.0004  -- minimum movement² per tick to not be "stuck"
    
        -- Sprint settings
        self.allowSprint   = self.config.allowSprint   ~= false
        self.sprintMinDist = self.config.sprintMinDist or 1.5  -- don't sprint within this range
    
        -- Rotation smoothing: pitch is dampened to look natural
        self.pitchDamping  = self.config.pitchDamping  or 0.15  -- how much pitch to apply (15%)
    
        -- ── Runtime state ───────────────────────────────────────────
        self.path      = nil   -- current path (array of {x,y,z})
        self.pathIdx   = 1     -- current waypoint index
        self.lastPos   = nil   -- last tick position for stuck detection
        self.ticksStuck = 0
        self.currentArriveDist = self.arriveDist  -- per-waypoint jittered value
    
        return self
    end
    
    --- Sets a new path to follow.
    --- @param path table Array of {x, y, z} waypoints
    function Executor:setPath(path)
        self.path = path
        self.pathIdx = 1
        self.ticksStuck = 0
        self.lastPos = nil
        -- Jitter the first arrive distance
        self.currentArriveDist = clamp(
            gaussRandom(self.arriveDist, self.arriveJitter),
            0.15, 0.6
        )
    end
    
    --- Clears the current path and releases all inputs.
    function Executor:clear()
        self:_releaseInputs()
        self.path = nil
        self.pathIdx = 1
        self.ticksStuck = 0
        self.lastPos = nil
    end
    
    --- Returns true if the executor has a path and hasn't finished.
    --- @return boolean
    function Executor:isActive()
        return self.path ~= nil and self.pathIdx <= #self.path
    end
    
    --- Returns the current waypoint index.
    --- @return number
    function Executor:getProgress()
        return self.pathIdx
    end
    
    --- Returns the total number of waypoints.
    --- @return number
    function Executor:getTotal()
        if not self.path then return 0 end
        return #self.path
    end
    
    --- Returns the number of stuck ticks.
    --- @return number
    function Executor:getStuckTicks()
        return self.ticksStuck
    end
    
    --- Main tick function. Call once per registerClientTick.
    --- Returns a status string: "walking", "arrived", "stuck", "idle"
    --- @return string status
    function Executor:tick()
        if not self.path or self.pathIdx > #self.path then
            return "idle"
        end
    
        local pos = player.getPos()
        local px, py, pz = pos.x, pos.y, pos.z
        local fpx, fpy, fpz = math.floor(px), math.floor(py), math.floor(pz)
    
        -- ── Advance waypoint when close enough ──────────────────────
        local wp = self.path[self.pathIdx]
        local arrSq = self.currentArriveDist * self.currentArriveDist
        local dxH = px - (wp.x + 0.5)
        local dzH = pz - (wp.z + 0.5)
        local distHSq = dxH * dxH + dzH * dzH
    
        if distHSq < arrSq and math.abs(py - wp.y) < 1.5 then
            self.pathIdx = self.pathIdx + 1
            self.ticksStuck = 0
    
            -- New jittered arrive distance for next waypoint (human inconsistency)
            self.currentArriveDist = clamp(
                gaussRandom(self.arriveDist, self.arriveJitter),
                0.15, 0.6
            )
    
            if self.pathIdx > #self.path then
                self:_releaseInputs()
                return "arrived"
            end
            wp = self.path[self.pathIdx]
        end
    
        -- ── Stuck detection ─────────────────────────────────────────
        if self.lastPos then
            local movedSq = (px - self.lastPos.x)^2 + (pz - self.lastPos.z)^2
            if movedSq < self.stuckThreshSq then
                self.ticksStuck = self.ticksStuck + 1
            else
                self.ticksStuck = math.max(0, self.ticksStuck - 2)  -- gradual recovery
            end
        end
        self.lastPos = { x = px, y = py, z = pz }
    
        if self.ticksStuck >= self.stuckTicks then
            self:_releaseInputs()
            return "stuck"
        end
    
        -- ── Look-ahead steering ─────────────────────────────────────
        -- Face a point several waypoints ahead for smoother pathing
        local lookIdx = math.min(self.pathIdx + self.lookahead - 1, #self.path)
        local lookWp  = self.path[lookIdx]
    
        -- ── Determine movement needs ────────────────────────────────
        local curWp  = self.path[self.pathIdx]
        local dy     = curWp.y - fpy   -- vertical delta to current waypoint
    
        -- Jump when next waypoint is above and player is on ground
        -- This is a REAL jump via the jump key — exactly what a human does
        local needJump = (dy >= 1) and player.isOnGround()
    
        -- Sprint when going flat or downhill and far enough from target
        -- A human sprints on straightaways and stops sprinting near turns
        local lookDistSq = (px - (lookWp.x + 0.5))^2 + (pz - (lookWp.z + 0.5))^2
        local canSprint  = self.allowSprint
            and (dy <= 0)
            and (lookDistSq > self.sprintMinDist * self.sprintMinDist)
    
        -- ── Humanized rotation ──────────────────────────────────────
        -- Calculate yaw/pitch to the look-ahead point
        -- Use setSilentRotation with movementCorrection=true so W key
        -- moves the player toward the target. This is server-side legit.
        local targetX = lookWp.x + 0.5
        local targetY = lookWp.y + 0.1   -- aim at feet level (natural)
        local targetZ = lookWp.z + 0.5
    
        local rot = world.getRotation(targetX, targetY, targetZ)
    
        -- Dampen pitch to look natural (humans barely look up/down when walking)
        local dampedPitch = rot.pitch * self.pitchDamping
    
        -- Apply rotation with movementCorrection — this makes W key follow the yaw
        -- visibleHead=false means the client camera doesn't jerk (server-side only)
        player.setSilentRotation(rot.yaw, dampedPitch, true, false)
    
        -- ── Apply real player inputs ────────────────────────────────
        -- These are REAL keyboard inputs — identical to a human pressing WASD
        input.setPressedForward(true)
        input.setPressedSprinting(canSprint)
        input.setPressedJump(needJump)
    
        -- Never press strafe or backward — humans walk forward with mouse steering
        input.setPressedBack(false)
        input.setPressedLeft(false)
        input.setPressedRight(false)
        input.setPressedSneak(false)
    
        return "walking"
    end
    
    --- Releases all movement inputs.
    function Executor:_releaseInputs()
        input.setPressedForward(false)
        input.setPressedBack(false)
        input.setPressedLeft(false)
        input.setPressedRight(false)
        input.setPressedJump(false)
        input.setPressedSneak(false)
        input.setPressedSprinting(false)
    end
    
    return Executor
    
end

__bundle_preload["libs/fivetone/renderer"] = function()
    -- ================================================================
    -- Fivetone / renderer.lua
    -- 3D path visualization: lines, waypoint markers, goal beacon
    -- Uses registerWorldRenderer context (ctx)
    -- ================================================================
    
    local Renderer = {}
    
    --- Renders the active path as a green line with waypoint dots.
    --- @param ctx table World render context from registerWorldRenderer
    --- @param path table Array of {x, y, z} waypoints
    --- @param pathIdx number Current waypoint index
    --- @param maxRender number Maximum waypoints to render ahead (default 200)
    function Renderer.drawPath(ctx, path, pathIdx, maxRender)
        if not path or #path < 2 then return end
        maxRender = maxRender or 200
    
        local endIdx = math.min(#path, pathIdx + maxRender)
    
        -- ── Path line ───────────────────────────────────────────────
        local pts = {}
        for i = pathIdx, endIdx do
            local wp = path[i]
            pts[#pts + 1] = { x = wp.x + 0.5, y = wp.y + 0.05, z = wp.z + 0.5 }
        end
    
        if #pts > 1 then
            ctx.renderLinesFromPoints(pts, 0, 230, 0, 255, 2.5, false)
        end
    
        -- ── Current target waypoint highlight ───────────────────────
        local wp = path[pathIdx]
        if wp then
            local box = {
                minX = wp.x,      minY = wp.y,      minZ = wp.z,
                maxX = wp.x + 1,  maxY = wp.y + 0.08, maxZ = wp.z + 1,
            }
            ctx.renderFilled(box, 0, 255, 80, 100, false)
            ctx.renderOutline(box, 0, 255, 80, 255, 2.0, false)
        end
    
        -- ── Small dots at upcoming waypoints ────────────────────────
        local dotEnd = math.min(pathIdx + 30, endIdx)
        for i = pathIdx, dotEnd do
            local wp2 = path[i]
            ctx.renderFilledCircle(
                wp2.x + 0.5, wp2.y + 0.05, wp2.z + 0.5,
                0.15, 8,
                0, 200, 0, 120, false
            )
        end
    end
    
    --- Renders a goal marker (beacon beam + outlined box + text label).
    --- @param ctx table World render context
    --- @param goal table Goal object with .type, .x, .y, .z fields
    function Renderer.drawGoal(ctx, goal)
        if not goal then return end
    
        local gx, gy, gz
    
        if goal.type == "block" or goal.type == "near" then
            gx, gy, gz = goal.x, goal.y, goal.z
        elseif goal.type == "xz" then
            local pos = player.getPos()
            gx, gz = goal.x, goal.z
            gy = math.floor(pos.y)
        elseif goal.type == "ylevel" then
            local pos = player.getPos()
            gx, gz = math.floor(pos.x), math.floor(pos.z)
            gy = goal.y
        elseif goal.type == "runaway" then
            gx, gz = goal.x, goal.z
            gy = math.floor(player.getPos().y)
        end
    
        if not gx then return end
    
        -- Beacon beam
        ctx.renderBeaconBeam(gx, gy, gz, 255, 165, 0)
    
        -- Bounding box
        local box = {
            minX = gx - 0.05,  minY = gy,      minZ = gz - 0.05,
            maxX = gx + 1.05,  maxY = gy + 2,  maxZ = gz + 1.05,
        }
        ctx.renderOutline(box, 255, 165, 0, 255, 3.0, true)
        ctx.renderFilled(box, 255, 165, 0, 30, true)
    
        -- Label
        ctx.renderText(
            gx + 0.5, gy + 3, gz + 0.5,
            "§6Goal: " .. goal:desc(),
            0.6, 255, 200, 0, true
        )
    end
    
    return Renderer
    
end

__bundle_preload["libs/fivetone/astar"] = function()
    -- ================================================================
    -- Fivetone / astar.lua
    -- 1:1 port of AStarPathFinder.kt
    -- A* with binary heap (decrease-key), longHash closed set,
    -- timeout/node-limit, and async cancellation
    -- ================================================================
    
    local PathNode   = __bundle_require("libs/fivetone/path_node")
    local BinaryHeap = __bundle_require("libs/fivetone/binary_heap")
    local MovResult  = __bundle_require("libs/fivetone/movement_result")
    local Moves      = __bundle_require("libs/fivetone/moves")
    
    local AStar = {}
    AStar.__index = AStar
    
    --- Creates a new A* pathfinder instance.
    --- @param startX number Start block X
    --- @param startY number Start block Y (feet level)
    --- @param startZ number Start block Z
    --- @param goal table Goal object (with :isAtGoal and :heuristic)
    --- @param costs table ActionCosts instance
    --- @param config table Configuration {timeoutMs, maxNodes, maxFallHeight}
    --- @return table AStarPathFinder instance
    function AStar.new(startX, startY, startZ, goal, costs, config)
        local self = setmetatable({}, AStar)
        self.startX = startX
        self.startY = startY
        self.startZ = startZ
        self.goal   = goal
        self.costs  = costs
        self.config = config or {}
        self.config.timeoutMs     = self.config.timeoutMs     or 8000
        self.config.maxNodes      = self.config.maxNodes       or 75000
        self.config.maxFallHeight = self.config.maxFallHeight  or 20
        self.closedSet   = {}     -- longHash → PathNode
        self.calculating = false
        self.nodesExplored = 0
        return self
    end
    
    --- Runs the A* calculation. MUST be called inside threads.startThread().
    --- @return table|nil path ({x,y,z}[] waypoints), boolean complete
    function AStar:calculatePath()
        self.calculating = true
    
        local openSet   = BinaryHeap.new()
        local startNode = PathNode.new(self.startX, self.startY, self.startZ, self.goal)
        local res       = MovResult.new()
        local goal      = self.goal
        local costs     = self.costs
        local maxFall   = self.config.maxFallHeight
    
        startNode.costSoFar = 0.0
        startNode.totalCost = startNode.costToEnd
        openSet:add(startNode)
    
        -- Store start in closed set
        local startHash = PathNode.longHash(self.startX, self.startY, self.startZ)
        self.closedSet[startHash] = startNode
    
        local count = 0
        local t0 = os.clock() * 1000
    
        -- Track best node for partial path fallback
        local bestNode = startNode
        local bestH    = startNode.costToEnd
    
        while not openSet:isEmpty() and self.calculating do
            count = count + 1
    
            -- Periodic checks: timeout, node limit, yield
            if count % 128 == 0 then
                local elapsed = os.clock() * 1000 - t0
                if elapsed > self.config.timeoutMs then
                    self.nodesExplored = count
                    self.calculating = false
                    return self:_buildPartialPath(bestNode), false
                end
                -- Yield to prevent game freeze
                threads.sleep(0)
            end
    
            if count > self.config.maxNodes then
                self.nodesExplored = count
                self.calculating = false
                return self:_buildPartialPath(bestNode), false
            end
    
            local currentNode = openSet:poll()
    
            -- Goal check
            if goal:isAtGoal(currentNode.x, currentNode.y, currentNode.z) then
                self.nodesExplored = count
                self.calculating = false
                return self:_reconstructPath(currentNode), true
            end
    
            -- Track best heuristic for partial path
            local curH = goal:heuristic(currentNode.x, currentNode.y, currentNode.z)
            if curH < bestH then
                bestH = curH
                bestNode = currentNode
            end
    
            -- Expand all 16 moves
            for _, move in ipairs(Moves) do
                res:reset()
                move.calculate(costs, currentNode.x, currentNode.y, currentNode.z, res, maxFall)
    
                local cost = res.cost
                if cost < costs.INF_COST then
                    local hash = PathNode.longHash(res.x, res.y, res.z)
                    local neighbourNode = self:_getNode(res.x, res.y, res.z, hash)
                    local neighbourCostSoFar = currentNode.costSoFar + cost
    
                    if neighbourNode.costSoFar > neighbourCostSoFar then
                        neighbourNode.parentNode = currentNode
                        neighbourNode.costSoFar  = neighbourCostSoFar
                        neighbourNode.totalCost  = neighbourCostSoFar + neighbourNode.costToEnd
    
                        if neighbourNode.heapPosition == -1 then
                            openSet:add(neighbourNode)
                        else
                            openSet:relocate(neighbourNode)
                        end
                    end
                end
            end
        end
    
        self.nodesExplored = count
        self.calculating = false
        return self:_buildPartialPath(bestNode), false
    end
    
    --- Gets or creates a node in the closed set.
    --- @param x number
    --- @param y number
    --- @param z number
    --- @param hash number longHash value
    --- @return table PathNode
    function AStar:_getNode(x, y, z, hash)
        local n = self.closedSet[hash]
        if not n then
            n = PathNode.new(x, y, z, self.goal)
            self.closedSet[hash] = n
        end
        return n
    end
    
    --- Reconstructs the full path from start to endNode via parent chain.
    --- @param endNode table PathNode
    --- @return table Array of {x, y, z} waypoints
    function AStar:_reconstructPath(endNode)
        local path = {}
        local node = endNode
        while node do
            table.insert(path, 1, { x = node.x, y = node.y, z = node.z })
            node = node.parentNode
        end
        return path
    end
    
    --- Builds a partial path to the best node reached.
    --- @param bestNode table PathNode with best heuristic
    --- @return table|nil Array of {x, y, z} waypoints, or nil
    function AStar:_buildPartialPath(bestNode)
        if not bestNode then return nil end
        local startHash = PathNode.longHash(self.startX, self.startY, self.startZ)
        local bestHash  = PathNode.longHash(bestNode.x, bestNode.y, bestNode.z)
        if bestHash == startHash then return nil end
    
        local path = self:_reconstructPath(bestNode)
        if #path > 1 then
            return path
        end
        return nil
    end
    
    --- Requests the pathfinder to stop calculating.
    function AStar:requestStop()
        if not self.calculating then return end
        self.calculating = false
    end
    
    return AStar
    
end

__bundle_preload["libs/fivetone/init"] = function()
    -- ================================================================
    -- Fivetone / init.lua
    -- Public API — __bundle_require("libs/fivetone/init") returns this module
    -- Orchestrates A*, path execution, rendering, and goal management
    -- ================================================================
    
    local ActionCosts = __bundle_require("libs/fivetone/action_costs")
    local AStar       = __bundle_require("libs/fivetone/astar")
    local PathObj     = __bundle_require("libs/fivetone/path")
    local Goals       = __bundle_require("libs/fivetone/goals")
    local Executor    = __bundle_require("libs/fivetone/path_executor")
    local Renderer    = __bundle_require("libs/fivetone/renderer")
    
    local Fivetone = {}
    
    -- ── State enum ──────────────────────────────────────────────────
    Fivetone.State = {
        IDLE    = "IDLE",
        PATHING = "PATHING",
        WALKING = "WALKING",
        STUCK   = "STUCK",
        DONE    = "DONE",
        FAILED  = "FAILED",
    }
    
    -- ── Internal state ──────────────────────────────────────────────
    local state      = Fivetone.State.IDLE
    local statusMsg  = "Idle"
    local goal       = nil     -- current goal object
    local path       = nil     -- current Path object
    local pathThread = nil     -- thread handle for async A*
    local astarInst  = nil     -- current AStarPathFinder instance
    local executor   = nil     -- PathExecutor instance
    local costs      = nil     -- ActionCosts instance
    
    -- ── Configuration ───────────────────────────────────────────────
    local cfg = {
        allowSprint    = true,
        allowDiagonal  = true,
        allowFall      = true,
        maxFallHeight  = 4,
        renderPath     = true,
        renderGoal     = true,
        timeoutMs      = 8000,
        maxNodes       = 75000,
        stuckTicks     = 60,
        lookahead      = 4,
        arriveDist     = 0.35,
        sprintMinDist  = 1.5,
        pitchDamping   = 0.15,
    }
    
    -- ── Initialize costs and executor ───────────────────────────────
    local function ensureInit()
        if not costs then
            costs = ActionCosts.new()
        end
        if not executor then
            executor = Executor.new({
                arriveDist   = cfg.arriveDist,
                lookahead    = cfg.lookahead,
                stuckTicks   = cfg.stuckTicks,
                allowSprint  = cfg.allowSprint,
                sprintMinDist = cfg.sprintMinDist,
                pitchDamping = cfg.pitchDamping,
            })
        end
    end
    
    -- ── Helper: get player feet position ────────────────────────────
    local function playerFeet()
        local pos = player.getPos()
        return math.floor(pos.x), math.floor(pos.y), math.floor(pos.z)
    end
    
    -- ── Helper: find valid start position ───────────────────────────
    local function findValidStart(sx, sy, sz)
        local MH = __bundle_require("libs/fivetone/movement_helper")
        if MH.canStandAtFeet(sx, sy, sz) then
            return sx, sy, sz
        end
        -- Scan nearby
        local offsets = {{0,0},{1,0},{-1,0},{0,1},{0,-1}}
        for _, d in ipairs(offsets) do
            if MH.canStandAtFeet(sx + d[1], sy, sz + d[2]) then
                return sx + d[1], sy, sz + d[2]
            end
        end
        -- Scan up/down
        for dy = -3, 3 do
            if dy ~= 0 and MH.canStandAtFeet(sx, sy + dy, sz) then
                return sx, sy + dy, sz
            end
        end
        return nil, nil, nil
    end
    
    -- ╔═══════════════════════════════════════════════════════════════╗
    -- ║  PUBLIC API                                                    ║
    -- ╚═══════════════════════════════════════════════════════════════╝
    
    --- Exposes goal constructors.
    Fivetone.Goal = {}
    
    function Fivetone.Goal.block(x, y, z)
        ensureInit()
        return Goals.block(x, y, z, costs)
    end
    
    function Fivetone.Goal.xz(x, z)
        ensureInit()
        return Goals.xz(x, z, costs)
    end
    
    function Fivetone.Goal.yLevel(y)
        ensureInit()
        return Goals.yLevel(y, costs)
    end
    
    function Fivetone.Goal.near(x, y, z, range)
        ensureInit()
        return Goals.near(x, y, z, range, costs)
    end
    
    function Fivetone.Goal.runAway(x, z, dist)
        ensureInit()
        return Goals.runAway(x, z, dist, costs)
    end
    
    --- Sets the active goal without starting pathfinding.
    --- @param goalObj table Goal object
    function Fivetone.setGoal(goalObj)
        goal = goalObj
    end
    
    --- Returns the current goal.
    --- @return table|nil
    function Fivetone.getGoal()
        return goal
    end
    
    --- Returns the current state string.
    --- @return string
    function Fivetone.getState()
        return state
    end
    
    --- Returns the status message.
    --- @return string
    function Fivetone.getStatusMsg()
        return statusMsg
    end
    
    --- Returns true if actively pathing or walking.
    --- @return boolean
    function Fivetone.isPathing()
        return state == Fivetone.State.PATHING or state == Fivetone.State.WALKING
    end
    
    --- Returns the current path waypoints.
    --- @return table|nil
    function Fivetone.getPath()
        if not path then return nil end
        return path:getRawPath()
    end
    
    --- Returns current progress {idx, total}.
    --- @return table
    function Fivetone.getProgress()
        if not executor then return { idx = 0, total = 0 } end
        return { idx = executor:getProgress(), total = executor:getTotal() }
    end
    
    --- Returns the number of nodes explored in the last A* run.
    --- @return number
    function Fivetone.getNodesExplored()
        if not astarInst then return 0 end
        return astarInst.nodesExplored
    end
    
    --- Updates configuration.
    --- @param opts table Key-value pairs to update
    function Fivetone.configure(opts)
        for k, v in pairs(opts) do
            cfg[k] = v
        end
        -- Recreate executor with new config
        executor = nil
        ensureInit()
    end
    
    --- Returns the current configuration.
    --- @return table
    function Fivetone.getConfig()
        return cfg
    end
    
    --- Cancels all pathfinding and walking.
    --- @param silent boolean If true, don't print a message
    function Fivetone.cancel(silent)
        if executor then executor:clear() end
        if pathThread then threads.stopThread(pathThread); pathThread = nil end
        if astarInst then astarInst:requestStop() end
        state = Fivetone.State.IDLE
        statusMsg = "Idle"
        path = nil
        astarInst = nil
        if not silent then
            player.addMessage("§c[Fivetone] Cancelled.")
        end
    end
    
    --- Starts pathfinding to the current goal.
    function Fivetone.path()
        if not goal then
            player.addMessage("§c[Fivetone] No goal set!")
            return
        end
    
        ensureInit()
    
        -- Kill any existing computation
        if pathThread then threads.stopThread(pathThread); pathThread = nil end
        if astarInst then astarInst:requestStop() end
        if executor then executor:clear() end
    
        state     = Fivetone.State.PATHING
        statusMsg = "Computing A*..."
        path      = nil
    
        pathThread = threads.startThread(function()
            local sx, sy, sz = playerFeet()
    
            -- Find valid start
            local vx, vy, vz = findValidStart(sx, sy, sz)
            if not vx then
                state = Fivetone.State.FAILED
                statusMsg = "Invalid start position"
                player.addMessage("§c[Fivetone] Invalid start position!")
                return
            end
    
            statusMsg = "A* from " .. vx .. "," .. vy .. "," .. vz .. "..."
    
            astarInst = AStar.new(vx, vy, vz, goal, costs, {
                timeoutMs     = cfg.timeoutMs,
                maxNodes      = cfg.maxNodes,
                maxFallHeight = cfg.maxFallHeight,
            })
    
            local waypoints, complete = astarInst:calculatePath()
    
            if waypoints and #waypoints >= 1 then
                path = PathObj.new(waypoints, complete, astarInst.nodesExplored)
                executor:setPath(waypoints)
                state = Fivetone.State.WALKING
    
                local tag = complete and "§a" or "§e"
                local label = complete and "Path found" or "Partial path"
                statusMsg = label .. " — " .. #waypoints .. " steps"
                player.addMessage(tag .. "[Fivetone] " .. label .. " — "
                    .. #waypoints .. " steps, " .. astarInst.nodesExplored .. " nodes")
            else
                state = Fivetone.State.FAILED
                statusMsg = "No path found (" .. astarInst.nodesExplored .. " nodes)"
                player.addMessage("§c[Fivetone] No path found! " .. statusMsg)
            end
        end)
    end
    
    --- Shortcut: set goal to (x,y,z) and start pathing.
    --- @param x number
    --- @param y number
    --- @param z number
    function Fivetone.goto(x, y, z)
        ensureInit()
        goal = Goals.block(x, y, z, costs)
        Fivetone.path()
    end
    
    --- Shortcut: set GoalXZ and start pathing.
    --- @param x number
    --- @param z number
    function Fivetone.gotoXZ(x, z)
        ensureInit()
        goal = Goals.xz(x, z, costs)
        Fivetone.path()
    end
    
    -- ╔═══════════════════════════════════════════════════════════════╗
    -- ║  TICK / RENDER HOOKS (called by autoload.lua)                ║
    -- ╚═══════════════════════════════════════════════════════════════╝
    
    --- Call this every tick from registerClientTick.
    function Fivetone.onTick()
        if state ~= Fivetone.State.WALKING then return end
        if not executor then return end
    
        local result = executor:tick()
    
        if result == "arrived" then
            -- Check if we actually reached the goal
            local px, py, pz = playerFeet()
            if goal and goal:isAtGoal(px, py, pz) then
                state = Fivetone.State.DONE
                statusMsg = "Goal reached!"
                player.addMessage("§a§l[Fivetone] Goal reached!")
            else
                state = Fivetone.State.DONE
                statusMsg = "End of path reached"
            end
        elseif result == "stuck" then
            player.addMessage("§e[Fivetone] Stuck! Recalculating...")
            Fivetone.path()  -- auto-recalculate
        end
    end
    
    --- Call this from registerWorldRenderer.
    --- @param ctx table World render context
    function Fivetone.onWorldRender(ctx)
        if cfg.renderPath and path and executor then
            Renderer.drawPath(ctx, path:getRawPath(), executor:getProgress())
        end
        if cfg.renderGoal then
            Renderer.drawGoal(ctx, goal)
        end
    end
    
    --- Call this from registerUnloadCallback.
    function Fivetone.onUnload()
        Fivetone.cancel(true)
        player.addMessage("§7[Fivetone] Unloaded.")
    end
    
    return Fivetone
    
end

return __bundle_require("libs/fivetone/init")