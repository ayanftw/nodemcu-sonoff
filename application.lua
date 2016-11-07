-- file : application.lua
local module = {}
m = mqtt.Client('sonoff-' .. config.ID, 120, config.MQTT_USER, config.MQTT_PASS)
m:on("connect", function(client) print("connected") end)
m:on("offline", function(client) print("offline") end)


relayPin = 6
buttonPin = 3
ledPin = 7
-- spare = 5

gpio.mode(relayPin, gpio.OUTPUT)
gpio.write(relayPin, gpio.LOW)

local buttonDebounce = 500
local buttonAlarmId = 2
gpio.mode(buttonPin, gpio.INPUT, gpio.PULLUP)

gpio.mode(ledPin, gpio.OUTPUT)
gpio.write(ledPin, gpio.HIGH)


local function flash_led(num)
    num = num or 1
    if (gpio.read(ledPin) == 1) then gpio.write(ledPin, gpio.HIGH) end
    for i=1,num,1
    do
        gpio.write(ledPin, gpio.LOW)
        tmr.alarm(5, 50, 0, function() gpio.write(ledPin, gpio.HIGH) end)
    end
end

local function mqtt_update()
    if (gpio.read(relayPin) == 0) then
        state = 'OFF'
    else
        state = 'ON'
    end
    m:publish(config.ENDPOINT .. config.ID .. "/state/", state, 0, 0)
    flash_led()
end


local function switch_relay(state)
    state = state or 1 -- switch on by default
    if (state == 1) then
        print("switching on")
        gpio.write(relayPin, gpio.HIGH)
    else
        print("switching off")
        gpio.write(relayPin, gpio.LOW)
    end
    if pcall(mqtt_update) then
        print("updating mqtt")
    else
        flash_led(3)
    end
end

local function toggle_relay()
    gpio.trig(buttonPin, "none")
    tmr.alarm(buttonAlarmId, buttonDebounce, tmr.ALARM_SINGLE, function()
        gpio.trig(buttonPin, "down", toggle_relay)
    end)
    if (gpio.read(relayPin) == 0) then
        switch_relay(1)
    else
        switch_relay(0)
    end
end

local function handle_message(client, topic, message)
    -- register message callback beforehand
    print("message")
    if message ~= nil then
        print(topic .. ": " .. message)
        if (message == 'ON' or message == 1) then
            switch_relay(1)
        elseif (message == 'OFF' or message == 0) then
            switch_relay(0)
        else
            print("invalid message (" .. message .. ")")
        end
    end
end
m:on("message", handle_message)

local function send_ping()
    m:publish(config.ENDPOINT .. "ping", "id=" .. config.ID, 0, 0)
end

local function register_client(client)
    -- subscribe to a topic and update the ping topic every 1000ms
    flash_led(2)
    topic = config.ENDPOINT .. config.ID
    client:subscribe(topic, 1, function(conn)
        print("subscribed at " .. topic)
    end)
    tmr.stop(6)
    tmr.alarm(6, 1000, 1,
    function()
        if not pcall(send_ping) then
            flash_led(2)
        end
    end)
end


local function mqtt_start()
    -- Connect to broker
    m:connect(config.MQTT_HOST, config.MQTT_PORT, 0, 1,
    register_client,
    function(client, reason)
        print("failed: " .. reason)
    end)
end

function module.start()
    mqtt_start()
end

gpio.trig(buttonPin, "down", toggle_relay)
return module
