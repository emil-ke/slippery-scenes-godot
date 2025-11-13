@tool
extends EditorPlugin

# ---  shortcut settings!!!
var shortcut_key = KEY_F
var shortcut_ctrl_pressed = true
# ---

var popup: PopupPanel
var line_edit: LineEdit
var list_view: ItemList
var shortcut: Shortcut
var opened_scenes: Array = []
var filtered_scenes: Array = []


func _enter_tree() -> void:
	set_process_unhandled_input(true)

	shortcut = Shortcut.new()
	var key_event = InputEventKey.new()
	key_event.keycode = shortcut_key
	key_event.ctrl_pressed = shortcut_ctrl_pressed
	key_event.command_or_control_autoremap = true
	shortcut.events = [key_event]

	popup = PopupPanel.new()
	popup.size = Vector2(400, 300)

	var vbox = VBoxContainer.new()
	popup.add_child(vbox)

	line_edit = LineEdit.new()
	line_edit.placeholder_text = "Search open scenes..."
	vbox.add_child(line_edit)

	list_view = ItemList.new()
	list_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_view.allow_rmb_select = false
	list_view.select_mode = ItemList.SELECT_SINGLE
	vbox.add_child(list_view)

	var base = EditorInterface.get_base_control()
	base.add_child(popup)

	line_edit.text_changed.connect(_on_text_changed)
	list_view.item_activated.connect(_on_item_activated)
	line_edit.gui_input.connect(_on_line_edit_input)


func _exit_tree() -> void:
	set_process_unhandled_input(false)
	if is_instance_valid(popup):
		popup.queue_free()
		popup = null


func _unhandled_input(event: InputEvent) -> void:
	if popup and popup.visible:
		if event is InputEventKey and event.pressed:
			match event.keycode:
				KEY_ESCAPE:
					popup.hide()
					get_viewport().set_input_as_handled()
					return
				KEY_ENTER:
					_open_selected_scene()
					get_viewport().set_input_as_handled()
					return

	# Open Popup
	if shortcut and shortcut.matches_event(event):
		if event is InputEventKey and not event.pressed:
			return
		_open_popup()


func _open_popup() -> void:
	_refresh_scene_list()
	popup.popup_centered(Vector2(400, 300))
	line_edit.clear()
	line_edit.grab_focus()


# The .tscn doesn't matter for fuzzy matching
func _normalize_scene_name(path: String) -> String:
	var name: String = path.get_file()
	if name.ends_with(".tscn"):
		name = name.substr(0, name.length() - 5)
	return name.to_lower()


func fuzzy_scoring(target: String, query: String) -> float:
	var t: String = target.to_lower()
	var q: String = query.to_lower()
	var t_len: int = t.length()
	var q_len: int = q.length()
	if q_len == 0:
		return 0.0
	var score: float = 0.0
	var t_idx: int = 0
	var q_idx: int = 0
	var consecutive: int = 0
	var first_match_bonus: float = 0.0

	while t_idx < t_len and q_idx < q_len:
		if t[t_idx] == q[q_idx]:
			var s: float = 1.0
			if consecutive > 0:
				s += consecutive * 2.0
			consecutive += 1
			# bonus for match at start of word (after underscore or first char)
			if t_idx == 0 or t[t_idx - 1] in ["_", " "]:
				s += 2.0
			# bonus for earlier positions in string (generally sensible, I think, though not in every case)
			s += 2.0 * (1.0 - float(t_idx) / float(t_len))
			score += s
			if first_match_bonus == 0.0:
				first_match_bonus = s

			q_idx += 1
		else:
			consecutive = 0
		t_idx += 1
	# penalize if query wasn't fully matched
	if q_idx < q_len:
		score *= 0.25
	return score


func _compare_scores_desc(a, b) -> int:
	return float(a["score"]) > float(b["score"])  # castring isn't actually neccessary here, for this impl., but it's safer, I guess


func _refresh_scene_list() -> void:
	list_view.clear()
	opened_scenes = EditorInterface.get_open_scenes()
	filtered_scenes = opened_scenes.duplicate()

	for path in filtered_scenes:
		list_view.add_item(_normalize_scene_name(path.get_file()))  # I don't know whether it's better to show with .tscn or not

	if list_view.item_count > 0:  # TODO: instead, maybe preserve selection if the curent item remains in the filtered set (doesn't really matter)
		list_view.select(0)


func _on_text_changed(new_text: String) -> void:
	list_view.clear()
	filtered_scenes.clear()

	if new_text == "":
		for path in opened_scenes:
			filtered_scenes.append(path)
			list_view.add_item(_normalize_scene_name(path.get_file()))
	else:
		var q: String = new_text.to_lower()
		var scored: Array = []

		for path in opened_scenes:
			var name: String = _normalize_scene_name(path)
			var score: float = fuzzy_scoring(name, q)
			scored.append(
				{"path": path, "name": _normalize_scene_name(path.get_file()), "score": score}
			)

		# sort descending (higher = better)
		scored.sort_custom(Callable(self, "_compare_scores_desc"))

		for entry in scored:
			filtered_scenes.append(entry["path"])
			list_view.add_item(entry["name"])

	if list_view.item_count > 0:
		list_view.select(0)


func _on_line_edit_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ENTER:
				_open_selected_scene()
				get_viewport().set_input_as_handled()
			KEY_DOWN:
				_move_selection(1)
				get_viewport().set_input_as_handled()
			KEY_UP:
				_move_selection(-1)
				get_viewport().set_input_as_handled()


func _move_selection(delta: int) -> void:
	if list_view.item_count == 0:
		return
	var sel = 0
	var sel_items = list_view.get_selected_items()
	if sel_items.size() > 0:
		sel = sel_items[0]
	sel = clamp(sel + delta, 0, list_view.item_count - 1)
	list_view.select(sel)
	list_view.ensure_current_is_visible()


func _on_item_activated(index: int) -> void:
	EditorInterface.open_scene_from_path(filtered_scenes[index])
	popup.hide()


func _open_selected_scene() -> void:
	if list_view.item_count == 0:
		return

	var selected = -1
	var sel_items = list_view.get_selected_items()
	if sel_items.size() > 0:
		selected = sel_items[0]
	else:
		selected = 0  # default to top

	EditorInterface.open_scene_from_path(filtered_scenes[selected])
	popup.hide()
