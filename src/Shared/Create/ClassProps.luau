type Source<T> = (() -> (T)) & ((newValue: T) -> ())
type V<T> = T--T | Source<T>

-- Base Instance type
type Instance = {
	Name: V<string>,
	ClassName: V<string>,
	Archivable: V<boolean>,
	Parent: V<Instance?>,
	[number]: any,
}

-- GuiBase2d - Base for all 2D UI elements
type GuiBase2d = Instance & {
	AbsolutePosition: V<Vector2>,
	AbsoluteRotation: V<number>,
	AbsoluteSize: V<Vector2>,
	AutoLocalize: V<boolean>,
	Clip: V<boolean>,
	Localize: V<boolean>,
	RootLocalizationTable: V<LocalizationTable?>,
	Selectable: V<boolean>,
	SelectionBehaviorDown: V<Enum.SelectionBehavior>,
	SelectionBehaviorLeft: V<Enum.SelectionBehavior>,
	SelectionBehaviorRight: V<Enum.SelectionBehavior>,
	SelectionBehaviorUp: V<Enum.SelectionBehavior>,
	SelectionGroup: V<boolean>,
	SelectionImageObject: V<GuiObject?>,
	SelectionOrder: V<number>,
}

-- GuiObject - Base for all interactive UI elements
type GuiObject = GuiBase2d & {
	Active: V<boolean>,
	AnchorPoint: V<Vector2>,
	AutomaticSize: V<Enum.AutomaticSize>,
	BackgroundColor3: V<Color3>,
	BackgroundTransparency: V<number>,
	BorderColor3: V<Color3>,
	BorderMode: V<Enum.BorderMode>,
	BorderSizePixel: V<number>,
	LayoutOrder: V<number>,
	NextSelectionDown: V<GuiObject?>,
	NextSelectionLeft: V<GuiObject?>,
	NextSelectionRight: V<GuiObject?>,
	NextSelectionUp: V<GuiObject?>,
	Position: V<UDim2>,
	Rotation: V<number>,
	Size: V<UDim2>,
	SizeConstraint: V<Enum.SizeConstraint>,
	Visible: V<boolean>,
	ZIndex: V<number>,
}

-- GuiButton - Base for clickable UI elements
type GuiButton = GuiObject & {
	AutoButtonColor: V<boolean>,
	Modal: V<boolean>,
	Selected: V<boolean>,
	Style: V<Enum.ButtonStyle>,
}

-- Frame
export type Frame = GuiObject & {
	Style: V<Enum.FrameStyle>,
}

-- ScrollingFrame
export type ScrollingFrame = GuiObject & {
	AutomaticCanvasSize: V<Enum.AutomaticSize>,
	BottomImage: V<string>,
	CanvasPosition: V<Vector2>,
	CanvasSize: V<UDim2>,
	ElasticBehavior: V<Enum.ElasticBehavior>,
	HorizontalScrollBarInset: V<Enum.ScrollBarInset>,
	MidImage: V<string>,
	ScrollBarImageColor3: V<Color3>,
	ScrollBarImageTransparency: V<number>,
	ScrollBarThickness: V<number>,
	ScrollingDirection: V<Enum.ScrollingDirection>,
	ScrollingEnabled: V<boolean>,
	TopImage: V<string>,
	VerticalScrollBarInset: V<Enum.ScrollBarInset>,
	VerticalScrollBarPosition: V<Enum.VerticalScrollBarPosition>,
}

-- TextLabel
export type TextLabel = GuiObject & {
	ContentText: V<string>,
	Font: V<Enum.Font>,
	FontFace: V<Font>,
	FontSize: V<Enum.FontSize>,
	LineHeight: V<number>,
	LocalizationMatchIdentifier: V<string>,
	LocalizationMatchedSourceText: V<string>,
	MaxVisibleGraphemes: V<number>,
	RichText: V<boolean>,
	Text: V<string>,
	TextBounds: V<Vector2>,
	TextColor3: V<Color3>,
	TextDirection: V<Enum.TextDirection>,
	TextFits: V<boolean>,
	TextScaled: V<boolean>,
	TextSize: V<number>,
	TextStrokeColor3: V<Color3>,
	TextStrokeTransparency: V<number>,
	TextTransparency: V<number>,
	TextTruncate: V<Enum.TextTruncate>,
	TextWrapped: V<boolean>,
	TextXAlignment: V<Enum.TextXAlignment>,
	TextYAlignment: V<Enum.TextYAlignment>,
}

-- TextButton
export type TextButton = GuiButton & {
	ContentText: V<string>,
	Font: V<Enum.Font>,
	FontFace: V<Font>,
	FontSize: V<Enum.FontSize>,
	LineHeight: V<number>,
	LocalizationMatchIdentifier: V<string>,
	LocalizationMatchedSourceText: V<string>,
	MaxVisibleGraphemes: V<number>,
	RichText: V<boolean>,
	Text: V<string>,
	TextBounds: V<Vector2>,
	TextColor3: V<Color3>,
	TextDirection: V<Enum.TextDirection>,
	TextFits: V<boolean>,
	TextScaled: V<boolean>,
	TextSize: V<number>,
	TextStrokeColor3: V<Color3>,
	TextStrokeTransparency: V<number>,
	TextTransparency: V<number>,
	TextTruncate: V<Enum.TextTruncate>,
	TextWrapped: V<boolean>,
	TextXAlignment: V<Enum.TextXAlignment>,
	TextYAlignment: V<Enum.TextYAlignment>,
}

-- TextBox
export type TextBox = GuiObject & {
	ClearTextOnFocus: V<boolean>,
	ContentText: V<string>,
	CursorPosition: V<number>,
	Font: V<Enum.Font>,
	FontFace: V<Font>,
	FontSize: V<Enum.FontSize>,
	LineHeight: V<number>,
	LocalizationMatchIdentifier: V<string>,
	LocalizationMatchedSourceText: V<string>,
	MaxVisibleGraphemes: V<number>,
	MultiLine: V<boolean>,
	PlaceholderColor3: V<Color3>,
	PlaceholderText: V<string>,
	RichText: V<boolean>,
	SelectionStart: V<number>,
	ShowNativeInput: V<boolean>,
	Text: V<string>,
	TextBounds: V<Vector2>,
	TextColor3: V<Color3>,
	TextDirection: V<Enum.TextDirection>,
	TextEditable: V<boolean>,
	TextFits: V<boolean>,
	TextScaled: V<boolean>,
	TextSize: V<number>,
	TextStrokeColor3: V<Color3>,
	TextStrokeTransparency: V<number>,
	TextTransparency: V<number>,
	TextTruncate: V<Enum.TextTruncate>,
	TextWrapped: V<boolean>,
	TextXAlignment: V<Enum.TextXAlignment>,
	TextYAlignment: V<Enum.TextYAlignment>,
}

-- ImageLabel
export type ImageLabel = GuiObject & {
	Image: V<string>,
	ImageColor3: V<Color3>,
	ImageRectOffset: V<Vector2>,
	ImageRectSize: V<Vector2>,
	ImageTransparency: V<number>,
	ResampleMode: V<Enum.ResamplerMode>,
	ScaleType: V<Enum.ScaleType>,
	SliceCenter: V<Rect>,
	SliceScale: V<number>,
	TileSize: V<UDim2>,
}

-- ImageButton
export type ImageButton = GuiButton & {
	HoverImage: V<string>,
	Image: V<string>,
	ImageColor3: V<Color3>,
	ImageRectOffset: V<Vector2>,
	ImageRectSize: V<Vector2>,
	ImageTransparency: V<number>,
	PressedImage: V<string>,
	ResampleMode: V<Enum.ResamplerMode>,
	ScaleType: V<Enum.ScaleType>,
	SliceCenter: V<Rect>,
	SliceScale: V<number>,
	TileSize: V<UDim2>,
}

-- VideoFrame
export type VideoFrame = GuiObject & {
	IsLoaded: V<boolean>,
	Resolution: V<Vector2>,
	TimeLength: V<number>,
	TimePosition: V<number>,
	Video: V<string>,
	Volume: V<number>,
}

-- ViewportFrame
export type ViewportFrame = GuiObject & {
	Ambient: V<Color3>,
	CurrentCamera: V<Camera?>,
	ImageColor3: V<Color3>,
	ImageTransparency: V<number>,
	LightColor: V<Color3>,
	LightDirection: V<Vector3>,
}

-- CanvasGroup
export type CanvasGroup = GuiObject & {
	GroupColor3: V<Color3>,
	GroupTransparency: V<number>,
}

-- UI Layout Objects
export type UILayout = Instance & {

}

export type UIListLayout = UILayout & {
	FillDirection: V<Enum.FillDirection>,
	HorizontalAlignment: V<Enum.HorizontalAlignment>,
	Padding: V<UDim>,
	SortOrder: V<Enum.SortOrder>,
	VerticalAlignment: V<Enum.VerticalAlignment>,
	Wraps: V<boolean>,
}

export type UIGridLayout = UILayout & {
	CellPadding: V<UDim2>,
	CellSize: V<UDim2>,
	FillDirection: V<Enum.FillDirection>,
	FillDirectionMaxCells: V<number>,
	HorizontalAlignment: V<Enum.HorizontalAlignment>,
	SortOrder: V<Enum.SortOrder>,
	StartCorner: V<Enum.StartCorner>,
	VerticalAlignment: V<Enum.VerticalAlignment>,
}

export type UITableLayout = UILayout & {
	FillEmptySpaceColumns: V<boolean>,
	FillEmptySpaceRows: V<boolean>,
	MajorAxis: V<Enum.TableMajorAxis>,
	Padding: V<UDim2>,
}

export type UIPageLayout = UILayout & {
	Animated: V<boolean>,
	Circular: V<boolean>,
	CurrentPage: V<GuiObject?>,
	EasingDirection: V<Enum.EasingDirection>,
	EasingStyle: V<Enum.EasingStyle>,
	FillDirection: V<Enum.FillDirection>,
	GamepadInputEnabled: V<boolean>,
	HorizontalAlignment: V<Enum.HorizontalAlignment>,
	Padding: V<UDim>,
	ScrollWheelInputEnabled: V<boolean>,
	SortOrder: V<Enum.SortOrder>,
	TouchInputEnabled: V<boolean>,
	TweenTime: V<number>,
	VerticalAlignment: V<Enum.VerticalAlignment>,
}

-- UI Constraint Objects
export type UIConstraint = Instance & {

}

export type UIAspectRatioConstraint = UIConstraint & {
	AspectRatio: V<number>,
	AspectType: V<Enum.AspectType>,
	DominantAxis: V<Enum.DominantAxis>,
}

export type UISizeConstraint = UIConstraint & {
	MaxSize: V<Vector2>,
	MinSize: V<Vector2>,
}

export type UITextSizeConstraint = UIConstraint & {
	MaxTextSize: V<number>,
	MinTextSize: V<number>,
}

-- UI Effect Objects
export type UICorner = Instance & {
	CornerRadius: V<UDim>,
}

export type UIStroke = Instance & {
	ApplyStrokeMode: V<Enum.ApplyStrokeMode>,
	Color: V<Color3>,
	LineJoinMode: V<Enum.LineJoinMode>,
	Thickness: V<number>,
	Transparency: V<number>,
}

export type UIGradient = Instance & {
	Color: V<ColorSequence>,
	Offset: V<Vector2>,
	Rotation: V<number>,
	Transparency: V<NumberSequence>,
}

export type UIPadding = Instance & {
	PaddingBottom: V<UDim>,
	PaddingLeft: V<UDim>,
	PaddingRight: V<UDim>,
	PaddingTop: V<UDim>,
}

export type UIScale = Instance & {
	Scale: V<number>,
}

-- Screen and Layer GUIs
export type LayerCollector = GuiBase2d & {
	Enabled: V<boolean>,
	ResetOnSpawn: V<boolean>,
	ZIndexBehavior: V<Enum.ZIndexBehavior>,
}

export type ScreenGui = LayerCollector & {
	ClipToDeviceSafeArea: V<boolean>,
	DisplayOrder: V<number>,
	IgnoreGuiInset: V<boolean>,
	SafeAreaCompatibility: V<Enum.SafeAreaCompatibility>,
	ScreenInsets: V<Enum.ScreenInsets>,
}

export type BillboardGui = LayerCollector & {
	Active: V<boolean>,
	Adornee: V<Instance?>,
	AlwaysOnTop: V<boolean>,
	Brightness: V<number>,
	ClipsDescendants: V<boolean>,
	DistanceStep: V<number>,
	DistanceLowerLimit: V<number>,
	DistanceUpperLimit: V<number>,
	ExtentsOffset: V<Vector3>,
	ExtentsOffsetWorldSpace: V<Vector3>,
	Face: V<Enum.NormalId>,
	LightInfluence: V<number>,
	MaxDistance: V<number>,
	PlayerToHideFrom: V<Player?>,
	Size: V<UDim2>,
	SizeOffset: V<Vector2>,
	StudsOffset: V<Vector3>,
	StudsOffsetWorldSpace: V<Vector3>,
}

export type SurfaceGui = LayerCollector & {
	Active: V<boolean>,
	Adornee: V<Instance?>,
	AlwaysOnTop: V<boolean>,
	Brightness: V<number>,
	CanvasSize: V<Vector2>,
	ClipsDescendants: V<boolean>,
	Face: V<Enum.NormalId>,
	LightInfluence: V<number>,
	MaxDistance: V<number>,
	PixelsPerStud: V<number>,
	SizingMode: V<Enum.SurfaceGuiSizingMode>,
	ToolPunchThroughDistance: V<number>,
	ZOffset: V<number>,
}

return nil