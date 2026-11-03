# 容器逐个入场/出场动画：
# 让一个容器（默认自身）的子控件按顺序依次出现或消失。
class_name ContainerTween extends VBoxContainer

# ==== 信号 ====
signal appear_started()
signal disappear_started()
signal appear_finished()
signal disappear_finished()



# 动画触发模式
enum PLAY_MODE {
	MANUAL,       # 手动调用
	ON_READY,     # 节点就绪时自动播放
}

# 动画类型
enum ANIMATION_TYPE {
	SCALE,        # 缩放出现
	SLIDE_IN,     # 从左侧滑入
}

# 子控件的动画顺序
enum ANIMATION_ORDER {
	FORWARD,      # 从上往下
	REVERSE,      # 从下往上
}


# ==== 子控件原始状态 ====

# 缓存子控件的原始属性，用于动画结束后恢复
class ChildState:
	var position: Vector2
	var position_ratio: Vector2
	var scale: Vector2
	var pivot: Vector2
	var pivot_ratio: Vector2
	var rotation: float
	var alpha: float
	var transform_enabled: bool
	var visual_only: bool


# ==== 导出属性 ====

# 动画作用的容器，未指定时使用自身
@export var target_container: Container
# 动画触发模式
@export var play_mode: PLAY_MODE = PLAY_MODE.ON_READY
# 动画类型
@export var animation_type: ANIMATION_TYPE = ANIMATION_TYPE.SCALE
# 子控件播放顺序
@export var animation_order: ANIMATION_ORDER = ANIMATION_ORDER.FORWARD
# 缩放动画的锚点比例（0~1，相对子控件自身），默认居中
@export var scale_pivot_ratio: Vector2 = Vector2(0.5, 0.5)
# 单个元素的动画时长
@export_range(0.01, 2.0, 0.01)
var element_duration: float = 0.25
# 整体动画开始前的延迟
@export_range(0.0, 2.0, 0.01)
var start_delay: float = 0.0
# 相邻元素之间的延迟
@export_range(0.0, 1.0, 0.005)
var stagger_delay: float = 0.075
# 淡入淡出时长
@export_range(0.01, 1.0, 0.01)
var fade_duration: float = 0.12
# 滑入和滑出的位移量
@export var slide_offset: Vector2 = Vector2(-60.0, 0.0)
# 是否只影响视觉，不影响鼠标输入区域
@export var visual_only: bool = true


# 当前正在播放的 Tween
var active_tween: Tween
# 缓存子控件的原始属性（Control -> ChildState）
var child_states: Dictionary = {}



func _ready() -> void:
	# 默认作用于自身
	if not target_container:target_container = self

	# 节点就绪后 自动触发
	if play_mode == PLAY_MODE.ON_READY:
		appear()




# 缓存控件的原始属性，返回 true 表示本次新增
func _cache_child(control: Control) -> bool:

	if child_states.has(control):return false

	var state := ChildState.new()

	state.transform_enabled = control.offset_transform_enabled
	state.visual_only = control.offset_transform_visual_only

	state.position = control.offset_transform_position
	state.position_ratio = control.offset_transform_position_ratio

	state.scale = control.offset_transform_scale

	state.pivot = control.offset_transform_pivot
	state.pivot_ratio = control.offset_transform_pivot_ratio

	state.rotation = control.offset_transform_rotation
	state.alpha = control.modulate.a

	child_states[control] = state

	return true


# 获取按照指定顺序排列的子控件
func _get_ordered_children() -> Array[Control]:

	var children: Array[Control] = []

	if not is_instance_valid(target_container):
		return children

	# 清理已被释放的子控件缓存
	for key in child_states.keys():
		if not is_instance_valid(key):
			child_states.erase(key)

	# 获取直接子控件，并缓存原始属性
	for child in target_container.get_children():

		if not child is Control:
			continue

		var control := child as Control
		_cache_child(control)
		children.append(control)

	# 根据设置调整播放顺序
	if animation_order == ANIMATION_ORDER.REVERSE:
		children.reverse()

	return children


# 恢复控件的原始变换属性
func _restore_child_transform(control: Control) -> void:

	if not is_instance_valid(control):
		return

	if not child_states.has(control):
		return

	var state: ChildState = child_states[control]

	# 恢复偏移变换属性
	control.offset_transform_position = state.position
	control.offset_transform_position_ratio = state.position_ratio

	control.offset_transform_scale = state.scale

	control.offset_transform_pivot = state.pivot
	control.offset_transform_pivot_ratio = state.pivot_ratio

	control.offset_transform_rotation = state.rotation

	control.offset_transform_visual_only = state.visual_only

	# 最后恢复启用状态
	control.offset_transform_enabled = state.transform_enabled


# ==== 动画状态准备 ====

# 启用并初始化偏移变换
func _prepare_transform(control: Control) -> void:

	control.offset_transform_enabled = true
	control.offset_transform_visual_only = visual_only

	if animation_type == ANIMATION_TYPE.SCALE:
		control.offset_transform_pivot = Vector2.ZERO
		control.offset_transform_pivot_ratio = scale_pivot_ratio


# 设置控件的入场动画起始状态
func _reset_to_start(control: Control) -> void:

	_prepare_transform(control)

	match animation_type:
		ANIMATION_TYPE.SCALE:
			control.offset_transform_scale = Vector2.ZERO
		ANIMATION_TYPE.SLIDE_IN:
			control.offset_transform_position = child_states[control].position + slide_offset

	# 初始透明度
	control.modulate.a = 0.0

	# 入场前恢复可见（上一次出场可能将其隐藏）
	control.visible = true


# ==== Tween 管理 ====

# 终止当前动画
func _kill_tween() -> void:

	if active_tween and active_tween.is_valid():
		active_tween.kill()

	active_tween = null


# 创建动画
func _create_tween(entering: bool) -> void:

	active_tween = create_tween()
	active_tween.set_parallel(true)

	var trans := Tween.TRANS_CUBIC
	var ease_type := Tween.EASE_IN_OUT

	if entering:
		if animation_type == ANIMATION_TYPE.SCALE:
			trans = Tween.TRANS_BACK

		ease_type = Tween.EASE_OUT

	active_tween.set_trans(trans)
	active_tween.set_ease(ease_type)


# ==== 入场 / 出场 ====

# 播放所有子控件的入场动画
func appear() -> void:
	_play(true)

# 播放所有子控件的出场动画
func disappear() -> void:
	_play(false)


# 统一播放入口：entering 为 true 入场，false 出场
func _play(entering: bool) -> void:

	# 终止之前的动画
	_kill_tween()

	# 固定本次动画的子控件列表
	var children := _get_ordered_children()

	# 初始化所有子控件
	for child in children:
		if entering:
			_reset_to_start(child)
		else:
			_prepare_transform(child)

	# 发出动画开始信号
	if entering:
		appear_started.emit()
	else:
		disappear_started.emit()

	# 没有子控件时直接结束
	if children.is_empty():

		if entering:
			appear_finished.emit()
		else:
			disappear_finished.emit()

		return

	# 创建 Tween
	_create_tween(entering)

	# 创建所有子控件的动画
	for i in children.size():
		_tween_child(children[i], i, entering)

	# 所有并行动画结束后执行回调
	active_tween.chain().tween_callback(
		_on_play_finished.bind(entering, children)
	)


# 创建单个子控件的动画
func _tween_child(child: Control, index: int, entering: bool) -> void:

	var state: ChildState = child_states[child]
	var delay := start_delay + stagger_delay * index

	# 根据动画类型确定目标属性和目标值
	var property: String
	var target_value: Vector2

	match animation_type:

		ANIMATION_TYPE.SCALE:
			property = "offset_transform_scale"
			target_value = state.scale if entering else Vector2.ZERO

		ANIMATION_TYPE.SLIDE_IN:
			property = "offset_transform_position"
			target_value = (
				state.position if entering
				else state.position + slide_offset
			)

	# 创建位移或缩放动画
	active_tween.tween_property(
		child,
		property,
		target_value,
		element_duration
	).set_delay(delay)

	# 创建透明度动画
	var target_alpha := state.alpha if entering else 0.0

	active_tween.tween_property(
		child,
		"modulate:a",
		target_alpha,
		fade_duration
	).set_delay(delay)


# ==== 动画结束 ====

# 入场 / 出场动画结束
func _on_play_finished(entering: bool, children: Array[Control]) -> void:

	for child in children:
		if not is_instance_valid(child):
			continue
		# 恢复原始变换属性
		_restore_child_transform(child)

		# 出场结束后彻底隐藏：不渲染、不参与鼠标命中
		if not entering:
			child.visible = false

	active_tween = null

	# 发出动画结束信号
	if entering:
		appear_finished.emit()
	else:
		disappear_finished.emit()
