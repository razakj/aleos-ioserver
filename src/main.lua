local sched = require 'sched'
local shell = require 'shell.telnet'
local log = require('log')
local server = require 'server'
local devicetree = require 'devicetree'
local modbus_lib = require 'modbus_lib'
local config = require 'config'
local http = require("socket.http")

log.setlevel("DEBUG", config.LOG_NAME)

modbus_lib.init(5,5, config.LOG_NAME);

local function setHandleError(res, msg)
	log(config.LOG_NAME, "ERROR", "%s", msg)
	res.result = -1
	res.errors[table.getn(res.errors)+1] = tostring(msg)
end

local function handleRequest(data, reply)
	local res = { result = 0, errors = {}, get = {}, modbus = {}}
	if data.set then
		for k,v in pairs(data.set) do
			if v.name then
				if v.value then
					devicetree.set(v.name, v.value)
					log(config.LOG_NAME, "INFO", "(REQUEST_HANDLER) %s changed to %s", v.name, v.value)
				else
					setHandleError(res, string.format("Value for %s is missing", v.name))
				end
			else
				setHandleError(res, string.format("Key for one of the SET commands is missing"))
			end	
		end
	end
	if data.get then
		for k,v in pairs(data.get) do
			res.get[v] = tostring(devicetree.get(v))
		end
	end
	if data.modbus then
		for k,v in pairs(data.modbus) do
			if v.address then
				local port = 502
				if v.port then
					port = v.port
				end
				if v.read then
					res.modbus[v.address] = {}
					log(config.LOG_NAME, "DEBUG", "(REQUEST_HANDLER) Modbus reading from %s", v.address)
					for k1,v1 in pairs(v.read) do
						if v1.type then
							if v1.address then
								local length = 1
								local modbusResult, err
								if v1.length and v1.type ~= "digitaloutput" and v1.type ~= "digitalinput" then
									length = v1.length
								end
								if v1.type == "holdingregister" then
									modbusResult, err = modbus_lib.readHoldingRegister(v.address, port, v1.address, length)
								elseif v1.type == "inputregister" then
									modbusResult, err = modbus_lib.readInputRegisters(v.address, port, v1.address, length)
								elseif v1.type == "digitaloutput" then
									modbusResult, err = modbus_lib.readCoils(v.address, port, v1.address)
								elseif v1.type == "digitalinput" then
									modbusResult, err = modbus_lib.readDiscreteInputs(v.address, port, v1.address)
								elseif v1.type == "long" then
									modbusResult, err = modbus_lib.readLong(v.address, port, v1.address, length)
								elseif v1.type == "float" then
									modbusResult, err = modbus_lib.readFloat(v.address, port, v1.address, length)
								else
									setHandleError(res, string.format("Unknown type under device %s and address %s", v.address, v1.address))
								end
								if err then
									setHandleError(res, string.format("Error while reading modbus register (%s, %s, %s)", v.address, v1.address, v1.type))
								else
									if modbusResult then
										local realLength = length
										local currLength = table.getn(res.modbus[v.address])
										if v1.type == "long" or v1.type == "float" then
											realLength = length / 2
										end
										for i=1, realLength do
											local realAddress = v1.address + i - 1
											if v1.type == "long" or v1.type == "float" then
												realLength = v1.address + ((i-1)*2) 
											end
											local singleRes = {
												address = v1.address,
												type = v1.type,
												value = modbusResult[i]
											}
											res.modbus[v.address][currLength+i] = singleRes
										end
									end
								end
							else
								setHandleError(res, string.format("Missing address for device %s and type %s", v.address, v1.type))
							end
						else
							setHandleError(res, string.format("Missing register type under device %s", v.address))
						end
					end
				end
				if v.write then
					log(config.LOG_NAME, "DEBUG", "(REQUEST_HANDLER) Modbus writing to %s", v.address)
					for k1,v1 in pairs(v.write) do
						if v1.type then
							if v1.address then
								if v1.value then
									if v1.type == "digitaloutput" then
										modbus_lib.writeCoil(v.address, port, v1.address, v1.value)
									elseif v1.type == "float" then
										modbus_lib.writeFloat(v.address, port, v1.address, v1.value)
									elseif v1.type == "long" then
										modbus_lib.writeLong(v.address, port, v1.address, v1.value)
									elseif v1.type == "holdingregister" then
										modbus_lib.writeRegister(v.address, port, v1.address, v1.value)
									else
										setHandleError(res, string.format("Unknown type under device %s and address %s", v.address, v1.address))
									end
								else 
									setHandleError(res, string.format("Missing value for %s/%s/%s", v1.type, v1.address, v.address))
								end
							else
								setHandleError(res, string.format("Missing address type under device %s and type %s", v.address, v1.type))
							end
						else
							setHandleError(res, string.format("Missing register type under device %s", v.address))
						end
					end
				end
			else
				setHandleError(res, string.format("Modbus address is missing"))
			end
		end
	end
	reply(res)
end

local function healthCheck()
	if config.HEALTH_CHECK_ENABLED then
		local missedPingsCounter = 0;
		while true do
			local r, c, h = http.request { method = "HEAD", url = config.HEALTH_CHECK_URL }
			if not r then
				missedPingsCounter = missedPingsCounter + 1
				log(config.LOG_NAME, "WARNING", "(HEALTH_CHECK) Missed ping to %s - %d out of %d", config.HEALTH_CHECK_URL, missedPingsCounter, config.HEALTH_CHECK_LIMIT)
			else
				log(config.LOG_NAME, "DEBUG", "(HEALTH_CHECK) %s accessible", config.HEALTH_CHECK_URL)
				missedPingsCounter = 0	
			end
			
			if missedPingsCounter == config.HEALTH_CHECK_LIMIT then
				log(config.LOG_NAME, "ERROR", "(HEALTH_CHECK) Missed pings limit to %s reached - %d out of %d", config.HEALTH_CHECK_URL, missedPingsCounter, config.HEALTH_CHECK_LIMIT)
				modbus_lib.writeCoil(config.HEALTH_CHECK_MODBUS_DEV, config.HEALTH_CHECK_MODBUS_PORT, config.HEALTH_CHECK_ERR_COIL, config.HEALTH_CHECK_ERR_VAL)	
			end 
			sched.wait(config.HEALTH_CHECK_INTERVAL)
		end
	end		
end

local function run()
	assert(devicetree.init())
	server.init(config.SERVER_HOST, config.SERVER_PORT, config.SERVER_KEY, config.LOG_NAME)
	server.listen(handleRequest)
end

local function main()
  sched.run(run)
  sched.run(healthCheck)
  sched.loop()
end

main()

