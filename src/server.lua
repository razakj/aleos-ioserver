local socket 	 = require "socket"
local log = require 'log'
local JSON = assert(loadfile "json.lua")()

local server = {}
local ADDRESS, PORT, AUTHKEY
local LOGNAME = "SOCKETSERVER"

local client

function server.init(address, port, authKey, logName)
	ADDRESS = address
	PORT = port
	AUTHKEY = authKey
	LOGNAME = logName
end

local function parseError(msg)
	local jsonMsg = string.format("{'error': '%s'}", msg)
	log(LOGNAME, "ERROR", string.format("(SERVER) %s", jsonMsg), msg)
	client:send(string.format("%s\n", jsonMsg))
	client:close()
end

JSON.onDecodeError = function(msg, text, location, etc)
	parseError(string.format("Error while parsing JSON - %s", text))
end

JSON.onDecodeOfNilError = function(msg, text, location, etc)
	parseError("Empty message received")
end

JSON.onDecodeOfHTMLError = function(msg, text, location, etc)
	parseError("HTML received instead of JSON")
end

JSON.onEncodeError = function(message, etc)
	parseError("Error while encoding the response")
end

function server.listen(callback)
	while true do
		local socketServer = assert(socket.bind(ADDRESS, PORT))
		log(LOGNAME, "DEBUG", "(SERVER) Listening")
		client = socketServer:accept()
		log(LOGNAME, "DEBUG", "(SERVER) Incoming connection")
		socketServer:close()
		client:settimeout(7)
		local data, err = client:receive()
	    if not err then 
	    	log(LOGNAME, "DEBUG", "(SERVER) Received : %s", data)
			local jsonData = JSON:decode(data)
	    	if jsonData then
	    		if jsonData.authKey then
	    			if tostring(jsonData.authKey) == AUTHKEY then
	    				callback(jsonData, function(res)
	    					if res then
		    					local jsonString = JSON:encode(res)
		    					if jsonString ~= "null" and jsonString then
		    						client:send(string.format("%s\n", jsonString))
		    					end
	    					end
	    				end)
	    			else
	    				parseError("Invalid authentication key")
	    			end
	    		else
	    			parseError("Missing authentication key")
	    		end
	    	end	
	    else
	    	log(LOGNAME, "ERROR", "(SERVER) Error : %s", err)
	    end
	    client:close()
	    log(LOGNAME, "DEBUG", "(SERVER) Connection closed")
    end
end

return server