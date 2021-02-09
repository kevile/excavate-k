
local tArgs = { ... }
if #tArgs ~= 1 then
    print( "Usage: excavate <diameter>" )
    return
end

-- Mine in a quarry pattern until we hit something we can't dig
local size = tonumber( tArgs[1] )
if size < 1 then
    print( "Excavate diameter must be positive" )
    return
end

local depth = 0
local unloaded = 0
local collected = 0

local xPos,zPos = 0,0
local xDir,zDir = 0,1

local goTo -- Filled in further down
local refuel -- Filled in further down

-- turt uses refuel(0) to test its inv for fuel items, keeps one stack if true

local function unload( _bKeepOneFuelStack )
    print( "Unloading items..." )
    for n=1,16 do
        local nCount = turtle.getItemCount(n)
        if nCount > 0 then
            turtle.select(n)
            local bDrop = true
            if _bKeepOneFuelStack and turtle.refuel(0) then
                bDrop = false
                _bKeepOneFuelStack = false
            end
            if bDrop then
                while not turtle.drop() do
                    print('Drop-off chest is full')
                    sleep(2)
                end
                unloaded = unloaded + nCount
            end
        end
    end
    collected = 0
    turtle.select(1)
end

-- turtle doesnt know the chest it empties into is already full

local function returnSupplies()
    local x,y,z,xd,zd = xPos,depth,zPos,xDir,zDir
    print( "Returning to surface..." )
    goTo( 0,0,0,0,-1 )

    local fuelNeeded = 2*(x+y+z) + 1 --fuel needed to return to the chest and back
    if not refuel( fuelNeeded ) then
        unload( true )
        print( "Waiting for fuel" )
        while not refuel( fuelNeeded ) do
            os.pullEvent( "turtle_inventory" ) -- http://www.computercraft.info/wiki/Os.pullEvent
        end
    else
        unload( true )
    end

    print( "Resuming mining..." )
    goTo( x,y,z,xd,zd )
end

-- gets called by tryforwards/down after a dig or attack operation
-- doesn't actually pick up items, just checks inventory fullness and updates log total
-- this should be called every time an item is newly picked up, to see if the inv became full
local function collect()
    local bFull = true
    local nTotalItems = 0
    -- counts items in all slots
    for n=1,16 do
        local nCount = turtle.getItemCount(n)
        if nCount == 0 then
            bFull = false
        end
        nTotalItems = nTotalItems + nCount
    end

    -- update item collection log
    if nTotalItems > collected then
        collected = nTotalItems
        if math.fmod(collected + unloaded, 50) == 0 then
            print( "Mined "..(collected + unloaded).." items." )
        end
    end

    -- starts as true, declared false if there are 0 slots empty (even if there is space for more in a stack)
    if bFull then
        print( "No empty slots left." )
        return false
    end
    return true
end

-- check for and loot the items from encountered chestst
local function lootChest(down) -- true if digging down

    if not down then
        local exists, data = turtle.inspect()
        if data.name == 'minecraft:chest' or data.name == 'appliedenergistics2:sky_stone_chest' then
            print('Detected a chest ahead! - ' .. data.name)
            while turtle.suck() do
                if not collect() then
                    returnSupplies()
                end
            end
        end
    else
        local exists, data = turtle.inspectDown()
        if data.name == 'minecraft:chest' or data.name == 'appliedenergistics2:sky_stone_chest' then
            print('Detected a chest below! - ' .. data.name)
            while turtle.suckDown() do
                if not collect() then
                    returnSupplies()
                end
            end
        end
    end
end

-- checks fuel level and returns true if there is 'enough'
-- enough can be specified by param or calculated from current loc if no param provided
function refuel( fuelNeeded )
    local fuelLevel = turtle.getFuelLevel()
    if fuelLevel == "unlimited" then
        return true
    end

    local needed = fuelNeeded or (xPos + zPos + depth + 2)
    if turtle.getFuelLevel() < needed then
        local fueled = false
        for n=1,16 do
            if turtle.getItemCount(n) > 0 then
                turtle.select(n)
                if turtle.refuel(1) then
                    while turtle.getItemCount(n) > 0 and turtle.getFuelLevel() < needed do
                        turtle.refuel(1)
                    end
                    if turtle.getFuelLevel() >= needed then
                        turtle.select(1)
                        return true
                    end
                end
            end
        end
        turtle.select(1)
        return false
    end

    return true
end

-- write a fn for digging 3 directions per move

local function tryForwards()
    if not refuel() then
        print( "Not enough Fuel" )
        returnSupplies()
    end

    while not turtle.forward() do
        if turtle.detect() then

            --check if it's a chest and loot if so
            lootChest()

            if turtle.dig() then
                if not collect() then
                    returnSupplies()
                end
            else
                return false
            end
        elseif turtle.attack() then
            if not collect() then
                returnSupplies()
            end
        else
            sleep( 0.05)
        end
    end

    xPos = xPos + xDir
    zPos = zPos + zDir
    return true
end

local function tryDown()
    if not refuel() then
        print( "Not enough Fuel" )
        returnSupplies()
    end

    while not turtle.down() do
        if turtle.detectDown() then

            --check if it's a chest and loot if so
            lootChest(true)

            if turtle.digDown() then
                if not collect() then
                    returnSupplies()
                end
            else
                return false
            end
        elseif turtle.attackDown() then
            if not collect() then
                returnSupplies()
            end
        else
            sleep( 0.05)
        end
    end

    depth = depth + 1
    if math.fmod( depth, 10 ) == 0 then
        print( "Descended "..depth.." metres." )
    end

    return true
end

local function turnLeft()
    turtle.turnLeft()
    xDir, zDir = -zDir, xDir
end

local function turnRight()
    turtle.turnRight()
    xDir, zDir = zDir, -xDir
end

function goTo( x, y, z, xd, zd )
    while depth > y do
        if turtle.up() then
            depth = depth - 1
        elseif turtle.digUp() or turtle.attackUp() then
            collect()
        else
            sleep( 0.05)
        end
    end

    if xPos > x then
        while xDir ~= -1 do
            turnLeft()
        end
        while xPos > x do
            if turtle.forward() then -- try to move
                xPos = xPos - 1
            elseif turtle.dig() or turtle.attack() then  -- couldnt move? try to dig or attack
                collect()
            else -- cant move dig or attack? wtf? wait half second for problem to clear
                sleep( 0.5) -- dont tweak this down
            end
        end
    elseif xPos < x then
        while xDir ~= 1 do
            turnLeft()
        end
        while xPos < x do
            if turtle.forward() then
                xPos = xPos + 1
            elseif turtle.dig() or turtle.attack() then
                collect()
            else
                sleep( 0.05)
            end
        end
    end

    if zPos > z then
        while zDir ~= -1 do
            turnLeft()
        end
        while zPos > z do
            if turtle.forward() then
                zPos = zPos - 1
            elseif turtle.dig() or turtle.attack() then
                collect()
            else
                sleep( 0.05)
            end
        end
    elseif zPos < z then
        while zDir ~= 1 do
            turnLeft()
        end
        while zPos < z do
            if turtle.forward() then
                zPos = zPos + 1
            elseif turtle.dig() or turtle.attack() then
                collect()
            else
                sleep( 0.05)
            end
        end
    end

    while depth < y do
        if turtle.down() then
            depth = depth + 1
        elseif turtle.digDown() or turtle.attackDown() then
            collect()
        else
            sleep( 0.05)
        end
    end

    while zDir ~= zd or xDir ~= xd do
        turnLeft()
    end
end


-- BEGIN MAIN PROCESS
if not refuel() then
    print( "Out of Fuel" )
    return
end

print( "Excavating..." )

turtle.select(1)

local alternate = 0
local done = false
while not done do
    for n=1,size do
        for m=1,size-1 do
            if not tryForwards() then
                done = true
                break
            end
        end
        if done then
            break
        end
        if n<size then
            if math.fmod(n + alternate,2) == 0 then
                turnLeft()
                if not tryForwards() then
                    done = true
                    break
                end
                turnLeft()
            else
                turnRight()
                if not tryForwards() then
                    done = true
                    break
                end
                turnRight()
            end
        end
    end
    if done then
        break
    end

    if size > 1 then
        if math.fmod(size,2) == 0 then
            turnRight()
        else
            if alternate == 0 then
                turnLeft()
            else
                turnRight()
            end
            alternate = 1 - alternate
        end
    end

    if not tryDown() then
        done = true
        break
    end
end

print( "Returning to surface..." )

-- Return to where we started
goTo( 0,0,0,0,-1 )
unload( false )
goTo( 0,0,0,0,1 )

print( "Mined "..(collected + unloaded).." items total." )
