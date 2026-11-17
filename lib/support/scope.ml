let ( let@ ) scope body = scope body
let on_exit finally body = Fun.protect ~finally body
