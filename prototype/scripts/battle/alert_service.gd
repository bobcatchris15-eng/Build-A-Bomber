class_name AlertService
extends Node
# Tracks battle events (under attack, construction complete) and provides 
# jumping to the latest event's location.

signal alert_posted(type: String, world_pos: Vector3)

const MAX_ALERTS := 10
const ALERT_TIMEOUT := 15.0

class Alert:
	var type: String
	var world_pos: Vector3
	var timestamp: float

var _alerts: Array[Alert] = []

func post_alert(type: String, world_pos: Vector3) -> void:
	var alert = Alert.new()
	alert.type = type
	alert.world_pos = world_pos
	alert.timestamp = Time.get_ticks_msec() / 1000.0
	
	_alerts.push_back(alert)
	if _alerts.size() > MAX_ALERTS:
		_alerts.pop_front()
		
	alert_posted.emit(type, world_pos)

func get_latest_alert() -> Alert:
	_cleanup()
	if _alerts.is_empty():
		return null
	return _alerts.back()

func get_active_alerts() -> Array[Alert]:
	_cleanup()
	return _alerts

func _cleanup() -> void:
	var now = Time.get_ticks_msec() / 1000.0
	_alerts = _alerts.filter(func(a): return now - a.timestamp < ALERT_TIMEOUT)
