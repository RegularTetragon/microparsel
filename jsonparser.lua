local P = require("parser")

language = {}
function json:json()
    return self:list() + self:dict()
end

function json:list()
    return P.bracketed(
        P.char("["),
        P.sepBy(
            self.value(),
            P.char(",")
        ),
        P.char("]"),
    )
end

function json:dict()
    return (
        P.char("{"):right(P.sepby(
            sequence(self:string(), P.char(":"), self:value()),
            P.char(",")
        )):left(P.char("}"))
    )
end


function json:string()
    return 
end