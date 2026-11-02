module het-cmp

// Heterogenous Eq and Ord

// Generic heterogenous inequality
pub fun het/(!=)(x : a, y : b, ?(==) : (a, b) -> e bool ) : e bool
  not(x==y)

// Generic heterogenous equality if `cmp` exists
pub fun het/(==)(x : a, y : b, ?cmp : (a, b) -> e order ) : e bool
  match cmp(x,y)
    Eq -> True
    _  -> False

// Generic heterogenous greater than
pub fun het/(>)(x : a, y : b, ?cmp : (a, b) -> e order ) : e bool
  cmp(x,y) == Gt

// Generic heterogenous lower than
pub fun het/(<)(x : a, y : b, ?cmp : (a, b) -> e order ) : e bool
  cmp(x,y) == Lt

// Generic heterogenous greater than or equal
pub fun het/(>=)(x : a, y : b, ?cmp : (a, b) -> e order ) : e bool
  not(x < y)

// Generic heterogenous lower than or equal
pub fun het/(<=)(x : a, y : b, ?cmp : (a, b) -> e order ) : e bool
  not(x > y)

