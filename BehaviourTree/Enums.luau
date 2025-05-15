export type Status = "SUCCESS" | "FAILURE" | "RUNNING"
export type NodeType = "SEQUENCE" | "FALLBACK" | "PARALLEL" | "DECORATOR" | "ACTION" | "CONDITION"

local Enums = {}

Enums.Status = {
    SUCCESS = "SUCCESS",
    FAILURE = "FAILURE",
    RUNNING = "RUNNING",
    IDLE = "IDLE",
}

Enums.NodeType = {
    SEQUENCE = "SEQUENCE",
    FALLBACK = "FALLBACK",
    PARALLEL = "PARALLEL",
    DECORATOR = "DECORATOR",
    ACTION = "ACTION",
    CONDITION = "CONDITION",
}

return Enums