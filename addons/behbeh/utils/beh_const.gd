class_name BehConst

## Return status for behaviors. Continue means the behavior is not done ticking.
## Success and Failure indicate the behavior has finished.
enum Status { Busy = 0, Resolved = 1, Failed = 2 }

## Positive infinity. Interpret as "not set" for floats.
const UNSET_FLOAT: float = INF
## Positive infinity. Interpret as "not set" for Vector2s.
const UNSET_VEC: Vector2 = Vector2(UNSET_FLOAT, UNSET_FLOAT)

