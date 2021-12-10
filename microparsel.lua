--A single file, Lua 5.1 compatible parsing library
local P = {}

local Either = {}
do -- Define Either
    local Left = {}
    local LeftMT = {
        __index = Left,
        __tostring = function(self)
            return "Left("..tostring(self.value)..")"
        end
    }
    local Right = {}
    local RightMT = {
        __index = Right,
        __tostring = function(self)
            return "Right("..tostring(self.value)..")"
        end
    }

    function Left.new(value)
        return setmetatable({value=value}, LeftMT)
    end

    function Left:bind(operation)
        return self
    end

    function Left:unwrap()
        error(self.value)
    end

    function Left:isRight()
        return false
    end

    function Left:map(_)
        return self
    end

    function Right.new(value)
        return setmetatable({value=value}, RightMT)
    end

    function Right:unwrap()
        return self.value
    end

    function Right:isRight()
        return true
    end

    function Right:map(f)
        return Right.new(f(self.value))
    end

    function Either.left(value)
        return Left.new(value)
    end

    function Either.right(value)
        return Right.new(value)
    end
end

local Parser = {}
local ParserMT = {__index=Parser}
local ParserError = {}
do -- Define Parser wrapper
    local ParserErrorMT = {__index=ParserError}

    function ParserError.new(expected, received)
        return setmetatable({
            expected = expected,
            received = received
        }, ParserErrorMT)
    end

    function ParserErrorMT:__tostring()
        return "Expected " .. self.expected .. " but received " .. self.received
    end

    --Construct a parser from a raw parsing function
    function Parser.new(parseFunc)
        -- parseFunc :: string -> string, a
        --  Takes a function which accepts a string,
        --  Parses some of it, puts the remainder string
        --  in as the first return value, and the result
        --  of the parsing into the second return value.
        --
        return setmetatable({
            parseFunc = parseFunc
        }, ParserMT)
    end

    --Take a string and parse it. If it fails, a descriptive
    --error message will be thrown.
    function Parser:parse(str)
        local remainder, result = self.parseFunc(str)
        return result:unwrap()
    end

    function Parser:tryParse(str)
        local remainder, result = self.parseFunc(str)
        if result:isRight() then
            return true, result:unwrap()
        else
            return false, tostring(result.value)
        end
    end

    --Take a function which takes a value and produces a parser.
    --First consume using self, pass the result to f, and then
    --consume using the result of f.
    function Parser:chain(f)
        return Parser.new(
            function(input)
                local remainder, result = self.parseFunc(input)
                if result:isRight() then
                    return f(result:unwrap()).parseFunc(remainder)
                else
                    return remainder, result
                end
            end
        )
    end

    function Parser:map(f)
        return Parser.new(
            function(input)
                local remainder, result = self.parseFunc(input)
                return remainder, result:map(input)
            end
        )
    end

    --Take another parser, consume its input and take its result,
    --ignore the result of self.
    function Parser:right(next)
        return Parser.new(
            function(input)
                local remainder, result = self.parseFunc(input)
                if result:isRight() then
                    return next.parseFunc(remainder)
                end
                return remainder, result
            end
        )
    end

    --Take another parser, consume its input but throw out its result,
    --The result of the combined parsers is the one the method is called
    --on.
    function Parser:left(next)
        return Parser.new(
            function(input)
                local remainder, result = self.parseFunc(input)
                if result:isRight() then
                    local secondRemainder, secondResult = next.parseFunc(remainder)
                    if secondResult:isRight() then
                        return secondRemainder, result
                    else
                        return input, secondResult
                    end
                end
                return remainder, result
            end
        )
    end

    --Parses using itself, throws out the result and returns a value.
    function Parser:result(value)
        return Parser.new(
            function(input)
                local remainder, result = self.parseFunc(input)
                if result:isRight() then
                    return remainder, Either.right(value)
                else
                    return remainder, result
                end
            end
        )
    end

    P.Parser = Parser
end

do -- Define simple parsers and combinators
    -- Parse any single character
    P.any = Parser.new(
        function(input)
            if #input == 0 then
                return "", Either.left(ParserError.new("any character", "end of stream"))
            else
                return string.sub(input, 2, -1), Either.right(string.sub(input, 1, 1)) 
            end
        end
    )

    -- Parse only an empty string
    P.endOfStream = Parser.new(
        function(input)
            if #input == 0 then
                return "", Either.right("")
            else
                return input, Either.left(ParserError.new("end of stream", input))
            end
        end
    )

    -- Always passes, consumes nothing, returns nil
    P.empty = Parser.new(
        function(input)
            return input, Either.right(nil)
        end
    )

    function P.try(parser)
        return Parser.new(
            function(input)
                remainder, result = parser.parseFunc(input)
                if result:isRight() then
                    return remainder, result
                else
                    return input, result
                end
            end
        )
    end

    function P.charPred(description, predicate)
        return try(P.any:chain(function(value)
            if predicate(value) then
                return Either.right(value)
            else
                return Either.left(ParserError(description, value))
            end
        end))
    end

    function P.choice(...)
        parsers = {...}
        return Parser.new(function(input)
            errors = {}
            for _, parser in ipairs(parsers) do
                remainder, result = P.try(parser).parseFunc(input)
                if result:isRight() then
                    return remainder, result
                else
                    table.insert(errors, result.value.expected)
                end
            end
            return input, Either.left(ParserError.new("one of the following: ".. table.concat(errors, ", "), input))
        end)
    end

    function P.match(pattern)
        assert(pattern, "pattern must not be nil")
        return Parser.new(function(input)
            left, right = string.find(input, pattern)
            if left == 1 then
                return string.sub(input, right + 1), Either.right(string.sub(input, left, right))
            else
                return input, Either.left(ParserError.new("pattern "..pattern, #input > 0 and input or "end of stream"))
            end
        end)
    end

    function P.many(parser)
        results = {}
        return Parser.new(
            function(input)
                while true do
                    remainder, result = parser.parseFunc(input)
                    if result:isRight() then
                        table.insert(results, result:unwrap())
                    else
                        return input, Either.right(results)
                    end
                    input = remainder
                end
            end
        )
    end

    function P.many1(parser)
        return Parser.new(
            function(input)
                result, value = parser.parseFunc(input)
                if value:isRight() then
                    extraResults = many(parser):parse(input)
                    table.insert(extraResults, 1, result)
                end
            end
        )
    end

    function P.sequence(...)
        local parsers = {...}
        return Parser.new(
            function(input)
                local results = {}
                for _, parser in pairs(parsers) do
                    local remainder, result = parser.parseFunc(input)
                    if not result:isRight() then
                        return remainder, result
                    end
                    table.insert(results, result:unwrap())
                    input = remainder
                end
                return input, Either.right(results)
            end
        )
    end

    function P.optional(parser, default)
        return Parser.new(function(input)
            remainder, result = parser.parseFunc(input)
            if result.isRight() then
                return remainder, result
            else
                return input, Either.right(default)
            end
        end)
    end

    function P.value(value)
        return P.empty:result(value)
    end

    function P.sepBy(separator, content)
        return P.many(
            content:left(P.optional(separator))
        )
    end

    function P.sepBy1(separator, content)
        return content:chain(
            function (result)
                P.many(
                    content:left(P.optional(separator))
                ):map(
                    function(data)
                        table.insert(data, 1, result)
                        return data
                    end
                )
            end
        )
    end

end


do -- Define Parser wrapper operators
    -- Choice
    function ParserMT:__add(other)
        return P.choice(self, other)
    end
    -- Sequence
    function ParserMT:__concat(other)
        return P.sequence(self, other)
    end
    -- Right (5.1 compatible)
    function ParserMT:__div(other)
        return self:right(other)
    end
    -- Left (5.1 compatible)
    function ParserMT:__mul(other)
        return self:left(other)
    end
    ParserMT.__shr = ParserMT.__div
    ParserMT.__shl = ParserMT.__mul
    
end
return P