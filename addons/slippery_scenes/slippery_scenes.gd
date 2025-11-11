@tool
extends EditorPlugin

var popup: PopupPanel
var line_edit: LineEdit
var list_view: ItemList
var shortcut: Shortcut
var opened_scenes: Array = []
var filtered_scenes: Array = []


func _enter_tree() -> void:
	set_process_unhandled_input(true)

	# Shortcut (Ctrl + f)
	shortcut = Shortcut.new()
	var key_event = InputEventKey.new()
	key_event.keycode = KEY_F
	key_event.ctrl_pressed = true
	key_event.command_or_control_autoremap = true
	shortcut.events = [key_event]

	# UI
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


func _refresh_scene_list() -> void:
	list_view.clear()
	opened_scenes = EditorInterface.get_open_scenes()
	filtered_scenes = opened_scenes.duplicate()

	for path in filtered_scenes:
		list_view.add_item(path.get_file())

	if list_view.item_count > 0:  # TODO: instead, maybe preserve selection if the curent item remains in the filtered set (doesn't really matter)
		list_view.select(0)


func _on_text_changed(new_text: String) -> void:
	list_view.clear()
	filtered_scenes.clear()

	for path in opened_scenes:
		if new_text == "" or path.to_lower().find(new_text.to_lower()) != -1:
			filtered_scenes.append(path)
			list_view.add_item(path.get_file())

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
