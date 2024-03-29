
local op = {}

function op.identity(...) return ... end
function op.K (v) return function () return v end end
function op.S (x) return function (y) return function (...) return x (...) (y (...)) end end end
function op.eternity() return op.eternity() end	-- via tail-recursion.
function op.noop() end
function op.pack_unpack (f) return op.o { table.pack, f, table.unpack } end
function op.forever(f, ...)
	local _f_ = op.pack_unpack (f)
	local v = table.pack(...)
	while true do v = _f_ (v) end
end
function op.precv (f, g) 
	return function (s, ...) if s then return f(...) else return g(...) end end 
end
function op.precv_before (f, g) 
	return function (...)
		f () 
		return op.precv (op.identity, g) (...)
	end 
end
function op.len(a) return #a end
function op.add(a, b) return a + b end
function op.add_l(a) return function (b) return a + b end end
function op.add_r(b) return function (a) return a + b end end
function op.eq(a, b) return a == b end
function op.lt(a, b) return a < b end
function op.le(a, b) return a <= b end
function op.increment(a) return op.add(a, 1) end
function op.apply (f, ...) return f(...) end
function op.o (funcs) return function (...) return table.foldr (funcs, op.apply, ...) end end
function op.call_pre_post (pre, f, post)
	return function (...)
		local tbl = table.pack (pre (...))
		local ret = table.pack (f (table.unpack (tbl)))
		post (table.unpack (tbl))
		return table.unpack (ret)
	end
end
function op.pcall_pre_post (pre, f, post)
	return op.call_pre_post (pre, function (...) return pcall (f, ...) end, post)
end
function op.string_format (str) return function (...) return string.format (str, ...) end end
function op.print_table (tbl) for k, v in pairs (tbl) do print (k, v) end end
function op.table_insert (tbl) return function (...) return table.insert (tbl, ...) end end
function op.fromtodo (from, to, step)
	step = step or 1
	return function (f) for i = from, to, step do f(i) end end 
end
function op.without_gc (f, h)

	h = h or error

	return function (...)

		local function R (s, ...)
			collectgarbage 'restart'
			if s then return ... else return h (...) end
		end

		collectgarbage 'stop'

		return R (pcall (f, ...))
	end
end
function op.ellipses_append (v)
	return function (...) return v, ... end
end
function op.assert_equals (expected, msg)
	return function (a) return assert (a == expected, msg) end 
end
function op.assert_true (msg) return op.assert_equals (true, msg) end

function op.table_insert (tbl)
	tbl = tbl or {}
	return function (v) 
		table.insert (tbl, v)
		return tbl
	end
end

function op.memoize (f)
	local computed, result_tbl = false, {}
	return function (...)
		if not computed then
			result_tbl = table.pack(f (...))
			computed = true
		end
		return table.unpack (result_tbl)
	end
end

function op.setfield (tbl) return function (k, v) tbl[k] = v end end

function op.callcc(f)
    return function (k)
		local co = coroutine.create(f)
		local function R (flag, ...) if flag then return (k or op.identity) (...) else error (...) end end
		return R (coroutine.resume(co, coroutine.yield))
	end
end


function op.with_elapsed_time_do (f, ...)
	return op.wrapping_around (os.clock, f, function (_, start) return os.clock () - start end) (...)
end

function op.wrapping_around (before, current, after, ...)

	local before_res = op.o { table.pack, before } (...)

	return function (...)
		local current_res = op.o { table.pack, current } (...)
		local after_res = after (current_res, table.unpack (before_res))
		return after_res, table.unpack (current_res)
	end

end


function op.add_trait (tbl, trait)

	--[[

	local b = {}

	setmetatable (b, {
		__index = { hello = 'world'}
	})


	local a = {}

	setmetatable (a, {
		__index = b
	})

	print (a.hello)

	]]

	local mt = getmetatable (tbl)

	if not mt then
		mt = {}
		setmetatable (tbl, mt)
	end

	local __index = mt.__index

	local f

	if __index then

		local g = __index

		if type (g) == 'table' then
			g = function (t, key) return __index[key] end
		end

		if type (trait) == 'table' then
			f = function (t, key) return trait[key] or g (t, key) end
		else
			f = function (t, key) return trait (t, key) or g (t, key) end
		end

	else 
		f = trait
	end

	mt.__index = f

	return tbl

end

--------------------------------------------------------------------------------

function coroutine.enumerate (co, f, ...)

	local function g (succeed, ...)
		
		local returned_values = table.pack (...)
		return succeed, returned_values
		
	end

	local values = table.pack (...)

	local i = 0
	while true do
		
		local succeed, packedtbl = g (coroutine.resume (co, table.unpack (values)))
		
		if not succeed then return succeed, packedtbl[1] end
		
		if packedtbl.n == 0 then break end   -- all ok, just finished to enumerate the solution space.
		
		i = i + 1
		values = table.pack (f (i, table.unpack (packedtbl)))
	end

	return true
end

function coroutine.const(f)

	local function C (...)
		operator.forever(coroutine.yield, f(...))
	end

	return coroutine.create(C)
end

function coroutine.mappend(...)

end

function coroutine.take (co, n)

	n = n or math.huge

	local function T ()
		local i, continue = 1, true
		while continue and i <= n do
			operator.frecv(coroutine.yield,
						   function () continue = false end,	-- simulate a break
						   coroutine.resume(co))
			i = i + 1
		end
	end

	return coroutine.create(T)
end

function coroutine.each(co, f)

	local continue = true
	local function stop () continue = false end

	while continue do
		operator.frecv(f, stop,	coroutine.resume(co))
	end

end

function coroutine.foldr (co, f, init)

	local function F (each)
		local folded = coroutine.foldr(co, f, init)
		return f(each, folded)
	end

	return operator.frecv(F, init, coroutine.resume(co))
end

function coroutine.iter (co)
	return function () return operator.recv(coroutine.resume(co)) end
end

function coroutine.nats(s)
	return coroutine.create(function ()
		local each = s or 0 -- initial value
		operator.forever(
			function ()
				coroutine.yield(each)
				each = each + 1
			end)
	end)
end

function coroutine.map(f)
	return function (co)
		return coroutine.create(
			function ()
				while true do
					local s, v = coroutine.resume(co)
					if s then coroutine.yield(f(v)) else break end
				end
			end)
	end
end

function coroutine.zip(co, another_co)
	return coroutine.create(
		function ()
			while true do
				local s, v = coroutine.resume(co)
				local r, w = coroutine.resume(another_co)
				if s and r then coroutine.yield(v, w) else break end
			end
		end)
end

function table.contains(tbl, elt)
	return tbl[elt] ~= nil
end

function table.foldr (tbl, f, ...)
	local init = table.pack (...)
	for i = #tbl, 1, -1 do init = table.pack(f(tbl[i], table.unpack (init))) end
	return table.unpack(init)
end

function table.map (tbl, f)
	mapped = {}
	for k, v in pairs(tbl) do mapped[k] = f(v) end
	return mapped
end

function table.scan (tbl, f, init)

	local scanned = {init}

	for k, v in ipairs (tbl) do
		init = f (init, v, k)
		table.insert (scanned, init)
	end

	return scanned

end

function table.unpack_named (names_tbl)
	return function (values_tbl)
		local tbl = {}
		for i, name in ipairs (names_tbl) do tbl[i] = values_tbl[name] end
		return table.unpack (tbl)
	end
end

function math.random_uniform(a, b)
	a = a or 0
	b = b or 1
	return a + (b - a) * math.random()
end

function math.random_bernoulli (p)

	if math.random() < p then return 1 else return 0 end
end

function math.random_bernoulli_boolean (p)

	return math.random_bernoulli(p) == 1
end

function math.random_binomial (n, p)

	local s, B = 0, math.random_bernoulli
	for i = 1, n do s = s + B (p) end
	return s
end

function math.random_geometric (p)
	
	local w, B = -1, math.random_bernoulli_boolean
	repeat w = w + 1 until B (p)
	return w
end

--[[
	def triangular(self, low=0.0, high=1.0, mode=None):
        """Triangular distribution.

        Continuous distribution bounded by given lower and upper limits,
        and having a given mode value in-between.

        http://en.wikipedia.org/wiki/Triangular_distribution

        """
        u = self.random()
        try:
            c = 0.5 if mode is None else (mode - low) / (high - low)
        except ZeroDivisionError:
            return low
        if u > c:
            u = 1.0 - u
            c = 1.0 - c
            low, high = high, low
        return low + (high - low) * _sqrt(u * c)

]]

function math.random_triangular (low, high, mode)
	local u, c = math.random(), 0.5

	if mode then c = (mode - low) / (high - low) end

	if c == math.huge then return low end

	if u > c then
		u = 1.0 - u
		c = 1.0 - c
		low, high = high, low
	end

	return low + (high - low) * math.sqrt(u * c)
end

--[[

    def normalvariate(self, mu, sigma):
        """Normal distribution.

        mu is the mean, and sigma is the standard deviation.

        """
        # Uses Kinderman and Monahan method. Reference: Kinderman,
        # A.J. and Monahan, J.F., "Computer generation of random
        # variables using the ratio of uniform deviates", ACM Trans
        # Math Software, 3, (1977), pp257-260.

        random = self.random
        while True:
            u1 = random()
            u2 = 1.0 - random()
            z = NV_MAGICCONST * (u1 - 0.5) / u2
            zz = z * z / 4.0
            if zz <= -_log(u2):
                break
        return mu + z * sigma
]]

local NV_MAGICCONST = 4 * math.exp(-0.5) / math.sqrt(2.0)
local LOG4 = math.log(4.0)
local SG_MAGICCONST = 1.0 + math.log(4.5)
local BPF = 53        		-- Number of bits in a float
local RECIP_BPF = 2 ^ (-BPF)

function math.random_normal (mu, sigma)

	local random, log, z = math.random, math.log, nil

    while true do
		local u1 = random()
		local u2 = 1.0 - random()
		z = NV_MAGICCONST * (u1 - 0.5) / u2
		local zz = z * z / 4.0
		if zz <= -log(u2) then break end
	end

	return mu + z * sigma

end

--[[
	def lognormvariate(self, mu, sigma):
        """Log normal distribution.

        If you take the natural logarithm of this distribution, you'll get a
        normal distribution with mean mu and standard deviation sigma.
        mu can have any value, and sigma must be greater than zero.

        """
        return _exp(self.normalvariate(mu, sigma))
]]
function math.random_lognormal(mu, sigma)

	assert (sigma > 0)

	return math.exp (math.normal (mu, sigma))
end

--[[
	def expovariate(self, lambd):
        """Exponential distribution.

        lambd is 1.0 divided by the desired mean.  It should be
        nonzero.  (The parameter would be called "lambda", but that is
        a reserved word in Python.)  Returned values range from 0 to
        positive infinity if lambd is positive, and from negative
        infinity to 0 if lambd is negative.

        """
        # lambd: rate lambd = 1/mean
        # ('lambda' is a Python reserved word)

        # we use 1-random() instead of random() to preclude the
        # possibility of taking the log of zero.
        return -_log(1.0 - self.random()) / lambd
]]
function math.random_exponential (lambd, mean)
	
	if mean then 
		-- in this case, `lambd` is the mean, so go transform it to an actual ratio.
		lambd = 1 / lambd 
	end

	return -math.log(1.0 - math.random()) / lambd
end

return op
