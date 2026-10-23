@tool
extends RefCounted
## The placement keys. Each is an editor shortcut under asset_drawer/, so it
## can be rebound in Editor Settings > Shortcuts and the binding persists.

enum Action { NONE, TURN_LEFT, TURN_RIGHT, TIP_FORWARD, TIP_SIDEWAYS, RESET }

## Action → [setting name, display name, default key, Shift, Alt].
const _DEFAULTS: Dictionary[Action, Array] = {
	Action.TURN_LEFT: ["turn_left", "Turn 90° Left", KEY_R, false, false],
	Action.TURN_RIGHT: ["turn_right", "Turn 90° Right", KEY_R, true, false],
	Action.TIP_FORWARD: ["tip_forward", "Tip 90° Forward", KEY_T, false, false],
	Action.TIP_SIDEWAYS: ["tip_sideways", "Tip 90° Sideways", KEY_T, true, false],
	Action.RESET: ["reset_rotation", "Reset Rotation", KEY_R, false, true],
}
const _PREFIX := "asset_drawer/"


## Adds any shortcut that isn't registered yet, leaving rebound ones alone.
static func register() -> void:
	var settings := EditorInterface.get_editor_settings()
	for action: Action in _DEFAULTS:
		var spec: Array = _DEFAULTS[action]
		var path: String = _PREFIX + spec[0]
		if settings.has_shortcut(path):
			continue
		var key := InputEventKey.new()
		key.keycode = spec[2]
		key.shift_pressed = spec[3]
		key.alt_pressed = spec[4]
		var shortcut := Shortcut.new()
		shortcut.resource_name = spec[1]
		shortcut.events = [key]
		settings.add_shortcut(path, shortcut)


## Which action [param event] triggers, or NONE.
static func action_for(event: InputEvent) -> Action:
	for action: Action in _DEFAULTS:
		var shortcut := _shortcut(action)
		if shortcut != null and shortcut.matches_event(event):
			return action
	return Action.NONE


## A one-line reminder of the current bindings, for the placement bar.
static func hint() -> String:
	return "%s / %s turn · %s / %s tip · %s reset · %s+wheel spin · Esc stop" % [
		_text(Action.TURN_LEFT), _text(Action.TURN_RIGHT),
		_text(Action.TIP_FORWARD), _text(Action.TIP_SIDEWAYS), _text(Action.RESET),
		"Option" if OS.get_name() == "macOS" else "Alt",
	]


static func _shortcut(action: Action) -> Shortcut:
	var path: String = _PREFIX + (_DEFAULTS[action][0] as String)
	var settings := EditorInterface.get_editor_settings()
	return settings.get_shortcut(path) if settings.has_shortcut(path) else null


static func _text(action: Action) -> String:
	var shortcut := _shortcut(action)
	return shortcut.get_as_text() if shortcut != null else "?"
