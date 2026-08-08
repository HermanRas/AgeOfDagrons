## Shared health-fraction thresholds and colours (PLAN.md 4.6), so a hurt entity
## reads the same way everywhere it is described: the dot drawn over it
## (EntityView) and the number in its detail panel (SelectionPanel).
class_name HealthDot
extends RefCounted

const HEALTHY_COLOR := Color(0.35, 1.0, 0.45)
const HURT_COLOR := Color(1.0, 0.7, 0.25)
const CRITICAL_COLOR := Color(1.0, 0.35, 0.3)

const HURT_FRACTION := 0.5
const CRITICAL_FRACTION := 0.25


static func color_for(fraction: float) -> Color:
	if fraction <= CRITICAL_FRACTION:
		return CRITICAL_COLOR
	if fraction <= HURT_FRACTION:
		return HURT_COLOR
	return HEALTHY_COLOR
