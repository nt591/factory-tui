let states = [ Model.Working; Model.Needs_you; Model.Ready ]
let of_state = function Model.Queued -> Model.Working | state -> state
let contains lane (task : Model.task) = of_state task.state = lane
