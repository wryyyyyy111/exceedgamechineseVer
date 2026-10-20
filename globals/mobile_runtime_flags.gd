class_name MobileRuntimeFlags
extends RefCounted

# All platforms use the mobile resource route so native and mobile runtimes load
# the same resized assets, including the phone/ OSS paths for large textures.
#todo 翻译：为true时，则网页端也走手机端加载路线（用于测试）
const DebugForceNativeMobileResourceRuntime := false
static func is_mobile_resource_runtime() -> bool:
	if DebugForceNativeMobileResourceRuntime:
		return true
	return OS.has_feature("web") and (
		OS.has_feature("mobile")
		or OS.has_feature("web_android")
		or OS.has_feature("web_ios")
	)
