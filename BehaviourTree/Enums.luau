export type Status = "SUCCESS" | "FAILURE" | "RUNNING"
export type NodeType = "SEQUENCE" | "FALLBACK" | "PARALLEL" | "DECORATOR" | "ACTION" | "CONDITION"
export type DebugLevel = number

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

Enums.DebugLevel = {
    NONE = 0,
    BASIC = 1,
    TRANSITIONS = 2,
    VERBOSE = 3,
}

return Enums