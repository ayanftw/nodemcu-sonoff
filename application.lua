-- file : application.lua
local module = {}  
m = nil

relayPin = 6
buttonPin = 3
ledPin = 7

gpio.mode(relayPin, gpio.OUTPUT)
gpio.write(relayPin, gpio.LOW)

buttonDebounce = 250
gpio.mode(buttonPin, gpio.INPUT, gpio.PULLUP)

gpio.mode(ledPin, gpio.OUTPUT)
gpio.write(ledPin, gpio.HIGH)

local function flash_led()
    if (gpio.read(ledPin) == 1) then gpio.write(ledPin, gpio.HIGH) end
    gpio.write(ledPin, gpio.LOW)
    tmr.alarm(5, 50, 0, function() gpio.write(ledPin, gpio.HIGH) end)
end


local function toggle_relay()
    tmr.delay(buttonDebounce)
    if (gpio.read(relayPin) == 0) then
        switch_relay(1)
    else
        switch_relay(0)
    end
end


-- Sends a simple ping to the broker
local function send_ping()  
    m:publish(config.ENDPOINT .. "ping","id=" .. config.ID,0,0)
end

-- Sends my id to the broker for registration
local function register_myself()  
    flash_led()
    m:subscribe(config.ENDPOINT .. config.ID, 0, function(conn)
        print("subscribed at " .. config.ENDPOINT .. config.ID)
    end)
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
    mqtt_update()
end


local function mqtt_start()  
    m = mqtt.Client('sonoff-' .. config.ID, 120, config.MQTT_USER, config.MQTT_PASS)
    -- register message callback beforehand
    m:on("message", function(conn, topic, data) 
      if data ~= nil then
        print(topic .. ": " .. data)
        if (data == 'ON' or data == 1) then
            switch_relay(1)
        elseif (data == 'OFF' or data == 0) then
            switch_relay(0)
        else
            print("invalid data (" .. data .. ")")
        end
      end
    end)

    m:on("connect", function(client) print("connected") end)
    m:on("offline", function(client) print("offline") end)

    -- Connect to broker
    m:connect(config.MQTT_HOST, config.MQTT_PORT, 0, 1,
    function(con) 
        register_myself()
        -- And then pings each 1000 milliseconds
        tmr.stop(6)
        tmr.alarm(6, 1000, 1, send_ping)
    end,
    function(client, reason) 
        print("failed: " .. reason)
    end) 

end

local function mqtt_update()
    if (gpio.read(relayPin) == 0) then
        state = 'OFF'
    else
        state = 'ON'
    end
    m.publish(config.ENDPOINT .. config.ID .. "/state/" .. state, 0, 0)
    flash_led()
end

function module.start()  
    mqtt_start()
end

gpio.trig(buttonPin, "down", toggle_relay)

return module 
