extends Node

var tests_ok := 0
var tests_names := []

func _ready():
	_run_utils_tests()
	print(str(tests_ok) + " test(s) run and passed.")	
	
	if tests_names.size() > 0:
		print("Successful named tests:")
		for name in tests_names:
			print("- " + name)

func _run_utils_tests():
	var url = "https://url"
	var result = PhoenixUtils.add_url_params(url)
	test(url == result)
	
	result = PhoenixUtils.add_url_params(url + "/", {foo = true})
	test(result == url + "/?foo=true")
	
	result = PhoenixUtils.add_url_params(url + "/?param=random&", {foo = true})
	test(result == url + "/?param=random&foo=true")
	
	result = PhoenixUtils.add_url_params(url, {foo = true})
	test(result == url + "?foo=true")
	
	result = PhoenixUtils.add_url_params(result, {bar = "baz", "number" = 12.5})
	test(result == url + "?foo=true&bar=baz&number=12.5")
	
	var mapped := []
	mapped = PhoenixUtils.map(Callable(self, "get_dict_ref"), [{ref = "1", foo = "bar"}, {ref = "godot"}])
	test(mapped == ["1", "godot"])
	
	mapped = PhoenixUtils.map(Callable(self, "get_dict_ref"), [{ref = "1", foo = "bar"}, {name = "godot"}])
	test(mapped == ["1", "godot"])	
	
	var filtered := []
	filtered = PhoenixUtils.filter(Callable(self, "filter_with_number"), [{ref = "1", number = 1}, {ref = "godot"}, {ref = "phoenix", number = 2}])
	test(filtered.size() == 2 and filtered[0].number == 1 and filtered[1].number == 2)
	
	filtered = PhoenixUtils.filter(Callable(self, "filter_with_number"), [{ref = "1"}, {ref = "godot"}, {ref = "phoenix"}, {}])
	test(filtered.is_empty())
	
func get_dict_ref(value):
	return value.ref if value.has("ref") else value.name
	
func filter_with_number(value):
	return value.has("number")

func test(condition : bool, name = null):
	assert(condition)
	tests_ok += 1
	if name: tests_names.append(name)
