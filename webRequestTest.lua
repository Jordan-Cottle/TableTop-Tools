
-- Initialize Block with button to start web request
buttonParameters = {
    click_function = 'startWebRequest',
    label = 'Hello',
    position = {0, 0.5, 0},
    width = 400,
    height = 400,
    function_owner = self
}
self.createButton(buttonParameters)

stats = {
    strength = 0,
    dexterity = 0,
    constitution = 0,
    intelligence = 0,
    wisdom = 0,
    charisma = 0
}

-- pull base stats out of the json table received
function parseStats(statsIn)
    for k, v in pairs(statsIn) do
        local id = v['id']
        local value = v['value']

        if id == 1 then
            stats['strength'] = value
        elseif id == 2 then
            stats['dexterity'] = value
        elseif id == 3 then
            stats['constitution'] = value
        elseif id == 4 then
            stats['intelligence'] = value
        elseif id == 5 then
            stats['wisdom'] = value
        elseif id == 6 then
            stats['charisma'] = value
        else
            print(id, 'not recognized')
        end
    end

    -- TODO Remove this after testing is done
    for k, v in pairs(stats) do
        print(k, v)
    end
end


function webRequestCallBack(webReturn)
    print('Web Request Returned')
    print('Data Received:')

    -- Decode json received into a lua table
    jsonTable = JSON.decode(webReturn.text)
    
    -- pick out important data and pass to parsing functions
    for k, v in pairs(jsonTable) do
        if k == 'stats' then
            parseStats(v)
        end
    end
end

-- Start a web request to receive DnD Beyond character sheet data in json form
function startWebRequest(object, color)
    print(self.getName(), ': Starting web request')
    WebRequest.get('https://www.dndbeyond.com/character/12044609/json', function(a) webRequestCallBack(a) end)
end