# The Setting Editor

The setting editor is a way for you to edit internal conditions & values.

The following are a list of settings which are present inside the setting editor, including the dropdown theyre located inside:

## Expand Behavior
    ### [bool] Auto Expand Ancestors on Select Unexpanded Instance
        If all ancestors to an instance should be expanded if you select one with unexpanded ancestors.

## Internal Behavior
    ### [float] ExplorerEntity Creation Cycle Interval
        The interval at which [ExplorerEntities](../scripting_api/internal_types.md) are created in bulk.

    ### [float] Queue Flush Cycle Interval
        The interval at which several internal queues are flushed, such as [ExplorerFrame](../scripting_api/internal_types.md) assignment, child added/removed actions, etc.

    ### [float] ExplorerFrame Reuse & HierarchyCache Rebuild Cycle Interval
        The interval at which [ExplorerFrames](../scripting_api/internal_types.md) are reused and the internal entity hierarchy caches are rebuilt

    ### [float] ExplorerEntity Cleanup Cycle Interval
        The interval at which [ExplorerEntities](../scripting_api/internal_types.md) are deleted and cleaned up.

## Saving Behavior
    ### [bool] Autosave Instance Changes
        If instance changes will be automatically saved by the internal version tracking system on an hourly basis.
    
    ### [bool] Save On Close
        If the SavedStateInstance of the plugin will be saved on close, or if it needs to be manually saved using the "Save State" button inside the dropdown menu.

## Scrolling Behavior
    ### [float] Virtual Scrolling Scroll Settle Time
        How long after you've stopped scrolling until the plugin will start reusing ExplorerFrames
    
    ### [float] Non-smooth Scroll Step
        How much you will scroll up/down per scroll step if you have SmoothScrolling disabled.
    
    ### [bool] Smooth Scroll Enabled
        If the plugin will use a custom fixed-step scrolling or Roblox's smooth scrolling for ScrollingFrames.
    
    ### [float] Non-smooth Scroll Threshold
        How much you need to move your scrolling wheel before scrolling starts if you have SmoothSccrolling disabled
    
    ### [float] Virtual Scrolling Instance Frame Buffer
        How much space of unreusable ExplorerFrames is left around the margins of the viewport to make reuse less visible

    ### [float] Virtual Frame Reuse Cooldown
        Cooldown for how often ExplorerFrames are allowed to be reused.

## Select Behavior

    ### [float] Cooldown to Double Click to Rename
        How much time needs to be inbetween 2 clicks at max in order to trigger rename
    
    ### [float] Cooldown to Double Click to Open Script
        How much time needs to be inbetween 2 clicks at max in order to trigger open script on LuaSourceContainer ExplorerFrames
    
    ### [bool] Property Editor Updated On Selection Change
        If the property editor should be updated on selection change (default is false because currently it causes lag due to unreused property frames)