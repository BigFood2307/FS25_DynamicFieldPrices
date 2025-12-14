
DFPUtil = {}

function DFPUtil:elementByName(elements, name)
    for e in elements do
        if e.name == name then
            return e
        end
    end
    return nil
end