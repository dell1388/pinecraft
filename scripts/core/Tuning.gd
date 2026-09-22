class_name Tuning
extends RefCounted

## Single place for the physics-budget knobs the stress test exercises.

# Per-plot ceiling on simultaneously simulated loose items. When exceeded the
# oldest item is recycled rather than freed, so there is no allocation spike.
const LOOSE_ITEMS_PER_PLOT := 200

# Hard clamps applied by LooseItemManager. Jolt has its own global ceiling
# (500 m/s) which is far too high to keep tunnelling and jitter under control.
const MAX_LINEAR_SPEED := 40.0
const MAX_ANGULAR_SPEED := 20.0

# Continuous collision detection is only worth its cost on genuinely fast
# bodies, so it is toggled on/off at runtime around this threshold.
const CCD_ENABLE_SPEED := 16.0
const CCD_DISABLE_SPEED := 10.0      # hysteresis, avoids per-frame flapping
const CCD_REVIEW_HZ := 10.0          # how often the manager re-evaluates CCD

# Round stock - trunks, branches, logs - is drawn as an octagon rather than as
# a smooth cylinder, to match the faceted land. The collision shape stays a true
# cylinder at the full radius, so the mesh always sits inside its own collider.
const ROUND_SIDES := 8

# Anything below this plane is teleported back to its plot spawn point.
const KILL_PLANE_Y := -25.0

# Sleep tuning is mirrored into the Jolt project settings; kept here so that
# gameplay code can reason about it.
const SLEEP_VELOCITY_THRESHOLD := 0.05
const SLEEP_TIME_THRESHOLD := 0.4

# Jolt sleeps per *island*: one twitching body keeps a whole 500-log pile awake,
# which measured at ~20 s to settle. The manager therefore force-sleeps any item
# that has been individually quiet for this long.
const QUIET_LINEAR_THRESHOLD := 0.12
const QUIET_ANGULAR_THRESHOLD := 0.4
const QUIET_TIME_TO_SLEEP := 0.5
