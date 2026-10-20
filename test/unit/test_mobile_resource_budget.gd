extends GutTest

func before_each():
	MobileResourceBudget.enabled_override = true
	MobileResourceBudget.reset()

func after_each():
	MobileResourceBudget.reset()
	MobileResourceBudget.enabled_override = null

func test_estimates_decoded_and_budget_memory():
	assert_almost_eq(MobileResourceBudget.estimate_decoded_mb(1024, 1024), 4.0, 0.001)
	assert_almost_eq(MobileResourceBudget.estimate_budget_mb(1024, 1024), 8.0, 0.001)

func test_register_unregister_and_warning_state():
	MobileResourceBudget.register_texture("a", 1536, 1536, "test", "visible")
	MobileResourceBudget.register_texture("b", 1536, 1536, "test", "visible")
	assert_eq(MobileResourceBudget.get_state(), "orange")
	assert_gt(MobileResourceBudget.warning_messages.size(), 0)

	MobileResourceBudget.unregister("a")
	assert_eq(MobileResourceBudget.get_state(), "green")

func test_can_block_noncritical_loads_but_allows_visible():
	MobileResourceBudget.register_texture("big", 4096, 4096, "test", "visible")
	assert_false(MobileResourceBudget.can_load("preview", 1024, 1024, "preview"))
	assert_true(MobileResourceBudget.can_load("visible", 1024, 1024, "visible"))

func test_unregister_owner_removes_matching_entries():
	MobileResourceBudget.register_texture("a", 1024, 1024, "one", "visible")
	MobileResourceBudget.register_texture("b", 1024, 1024, "two", "visible")
	MobileResourceBudget.unregister_owner("one")
	assert_false(MobileResourceBudget.entries.has("a"))
	assert_true(MobileResourceBudget.entries.has("b"))